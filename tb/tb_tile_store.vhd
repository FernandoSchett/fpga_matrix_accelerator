library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_tile_store is
end entity tb_tile_store;

architecture sim of tb_tile_store is

    constant CLK_PERIOD       : time := 10 ns;
    constant TILE_SIZE        : positive := 2;
    constant ELEMENT_WIDTH    : positive := 32;
    constant SDRAM_DATA_WIDTH : positive := 32;
    constant SDRAM_ADDR_WIDTH : positive := 8;
    constant TILE_ADDR_WIDTH  : positive := 3;

    signal clk : std_logic := '0';
    signal rst : std_logic := '0';

    signal store_start : std_logic := '0';
    signal store_busy  : std_logic;
    signal store_done  : std_logic;

    signal store_req     : std_logic;
    signal store_we      : std_logic;
    signal store_addr    : unsigned(SDRAM_ADDR_WIDTH-1 downto 0);
    signal store_wdata   : std_logic_vector(SDRAM_DATA_WIDTH-1 downto 0);
    signal store_byte_en : std_logic_vector((SDRAM_DATA_WIDTH/8)-1 downto 0);
    signal store_ready   : std_logic;

    signal host_req   : std_logic := '0';
    signal host_we    : std_logic := '0';
    signal host_addr  : unsigned(SDRAM_ADDR_WIDTH-1 downto 0) := (others => '0');
    signal host_wdata : std_logic_vector(SDRAM_DATA_WIDTH-1 downto 0) := (others => '0');
    signal host_rdata : std_logic_vector(SDRAM_DATA_WIDTH-1 downto 0);
    signal host_rvalid : std_logic;

    signal mem_req     : std_logic;
    signal mem_we      : std_logic;
    signal mem_addr    : unsigned(SDRAM_ADDR_WIDTH-1 downto 0);
    signal mem_wdata   : std_logic_vector(SDRAM_DATA_WIDTH-1 downto 0);
    signal mem_byte_en : std_logic_vector((SDRAM_DATA_WIDTH/8)-1 downto 0);
    signal mem_ready   : std_logic;
    signal mem_rvalid  : std_logic;
    signal mem_rdata   : std_logic_vector(SDRAM_DATA_WIDTH-1 downto 0);

    signal store_tile_addr : unsigned(TILE_ADDR_WIDTH-1 downto 0);
    signal tile_rd_data    : signed(ELEMENT_WIDTH-1 downto 0);

    signal tb_tile_wr_en   : std_logic := '0';
    signal tb_tile_addr    : unsigned(TILE_ADDR_WIDTH-1 downto 0) := (others => '0');
    signal tb_tile_wr_data : signed(ELEMENT_WIDTH-1 downto 0) := (others => '0');
    signal buf_addr        : unsigned(TILE_ADDR_WIDTH-1 downto 0);

    signal store_active : std_logic;

begin

    clk <= not clk after CLK_PERIOD / 2;

    store_active <= store_busy or store_start;

    mem_req     <= store_req when store_active = '1' else host_req;
    mem_we      <= store_we when store_active = '1' else host_we;
    mem_addr    <= store_addr when store_active = '1' else host_addr;
    mem_wdata   <= store_wdata when store_active = '1' else host_wdata;
    mem_byte_en <= store_byte_en when store_active = '1' else (others => '1');

    store_ready <= mem_ready when store_active = '1' else '0';
    host_rdata  <= mem_rdata;
    host_rvalid <= mem_rvalid when store_active = '0' else '0';

    buf_addr <= store_tile_addr when store_active = '1' else tb_tile_addr;

    u_mem : entity work.sdram_model
        generic map (
            DATA_WIDTH => SDRAM_DATA_WIDTH,
            ADDR_WIDTH => SDRAM_ADDR_WIDTH,
            DEPTH      => 256
        )
        port map (
            clk     => clk,
            rst     => rst,
            req     => mem_req,
            we      => mem_we,
            addr    => mem_addr,
            wdata   => mem_wdata,
            byte_en => mem_byte_en,
            ready   => mem_ready,
            rvalid  => mem_rvalid,
            rdata   => mem_rdata
        );

    u_buffer : entity work.tile_buffer_m10k
        generic map (
            ELEMENT_WIDTH => ELEMENT_WIDTH,
            ADDR_WIDTH    => TILE_ADDR_WIDTH,
            DEPTH         => 8
        )
        port map (
            clk     => clk,
            wr_en   => tb_tile_wr_en,
            addr    => buf_addr,
            wr_data => tb_tile_wr_data,
            rd_data => tile_rd_data
        );

    u_store : entity work.tile_store
        generic map (
            TILE_SIZE        => TILE_SIZE,
            ELEMENT_WIDTH    => ELEMENT_WIDTH,
            SDRAM_DATA_WIDTH => SDRAM_DATA_WIDTH,
            SDRAM_ADDR_WIDTH => SDRAM_ADDR_WIDTH
        )
        port map (
            clk           => clk,
            rst           => rst,
            start         => store_start,
            base_addr     => to_unsigned(20, SDRAM_ADDR_WIDTH),
            row_stride    => to_unsigned(4, SDRAM_ADDR_WIDTH),
            busy          => store_busy,
            done          => store_done,
            sdram_req     => store_req,
            sdram_we      => store_we,
            sdram_addr    => store_addr,
            sdram_wdata   => store_wdata,
            sdram_byte_en => store_byte_en,
            sdram_ready   => store_ready,
            tile_rd_addr  => store_tile_addr,
            tile_rd_data  => tile_rd_data
        );

    stim_proc : process
        variable expected_addr : natural;
        variable expected_val  : natural;
    begin
        rst <= '1';
        wait for 3 * CLK_PERIOD;
        rst <= '0';
        wait until rising_edge(clk);

        for idx in 0 to 3 loop
            tb_tile_addr    <= to_unsigned(idx, TILE_ADDR_WIDTH);
            tb_tile_wr_data <= to_signed(100 + idx, ELEMENT_WIDTH);
            tb_tile_wr_en   <= '1';
            wait until rising_edge(clk);
            tb_tile_wr_en <= '0';
            wait until rising_edge(clk);
        end loop;

        store_start <= '1';
        wait until rising_edge(clk);
        store_start <= '0';

        for cycle_idx in 0 to 100 loop
            wait until rising_edge(clk);
            exit when store_done = '1';
        end loop;

        assert store_done = '1'
            report "tile_store nao finalizou."
            severity failure;

        for idx in 0 to 3 loop
            if idx < 2 then
                expected_addr := 20 + idx;
            else
                expected_addr := 20 + 4 + (idx - 2);
            end if;

            expected_val := 100 + idx;

            host_addr <= to_unsigned(expected_addr, SDRAM_ADDR_WIDTH);
            host_we   <= '0';
            host_req  <= '1';
            wait until rising_edge(clk);
            host_req <= '0';
            wait for 1 ns;

            assert host_rvalid = '1' and host_rdata = std_logic_vector(to_signed(expected_val, SDRAM_DATA_WIDTH))
                report "tile_store gravou valor incorreto na SDRAM."
                severity failure;
        end loop;

        report "SIM_RESULT: PASS" severity note;
        finish;
    end process;

end architecture sim;
