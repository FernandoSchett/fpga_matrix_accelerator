library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_tile_loader is
end entity tb_tile_loader;

architecture sim of tb_tile_loader is

    constant CLK_PERIOD       : time := 10 ns;
    constant TILE_SIZE        : positive := 2;
    constant ELEMENT_WIDTH    : positive := 8;
    constant SDRAM_DATA_WIDTH : positive := 32;
    constant SDRAM_ADDR_WIDTH : positive := 8;
    constant TILE_ADDR_WIDTH  : positive := 3;

    signal clk : std_logic := '0';
    signal rst : std_logic := '0';

    signal loader_start : std_logic := '0';
    signal loader_busy  : std_logic;
    signal loader_done  : std_logic;

    signal loader_req     : std_logic;
    signal loader_we      : std_logic;
    signal loader_addr    : unsigned(SDRAM_ADDR_WIDTH-1 downto 0);
    signal loader_wdata   : std_logic_vector(SDRAM_DATA_WIDTH-1 downto 0);
    signal loader_byte_en : std_logic_vector((SDRAM_DATA_WIDTH/8)-1 downto 0);
    signal loader_ready   : std_logic;
    signal loader_rvalid  : std_logic;
    signal loader_rdata   : std_logic_vector(SDRAM_DATA_WIDTH-1 downto 0);

    signal host_req   : std_logic := '0';
    signal host_we    : std_logic := '0';
    signal host_addr  : unsigned(SDRAM_ADDR_WIDTH-1 downto 0) := (others => '0');
    signal host_wdata : std_logic_vector(SDRAM_DATA_WIDTH-1 downto 0) := (others => '0');

    signal mem_req     : std_logic;
    signal mem_we      : std_logic;
    signal mem_addr    : unsigned(SDRAM_ADDR_WIDTH-1 downto 0);
    signal mem_wdata   : std_logic_vector(SDRAM_DATA_WIDTH-1 downto 0);
    signal mem_byte_en : std_logic_vector((SDRAM_DATA_WIDTH/8)-1 downto 0);
    signal mem_ready   : std_logic;
    signal mem_rvalid  : std_logic;
    signal mem_rdata   : std_logic_vector(SDRAM_DATA_WIDTH-1 downto 0);

    signal tile_wr_en   : std_logic;
    signal tile_wr_addr : unsigned(TILE_ADDR_WIDTH-1 downto 0);
    signal tile_wr_data : signed(ELEMENT_WIDTH-1 downto 0);

    signal tb_tile_addr : unsigned(TILE_ADDR_WIDTH-1 downto 0) := (others => '0');
    signal buf_addr     : unsigned(TILE_ADDR_WIDTH-1 downto 0);
    signal buf_rd_data  : signed(ELEMENT_WIDTH-1 downto 0);

    signal loader_active : std_logic;

begin

    clk <= not clk after CLK_PERIOD / 2;

    loader_active <= loader_busy or loader_start or tile_wr_en;

    mem_req     <= loader_req when loader_active = '1' else host_req;
    mem_we      <= loader_we when loader_active = '1' else host_we;
    mem_addr    <= loader_addr when loader_active = '1' else host_addr;
    mem_wdata   <= loader_wdata when loader_active = '1' else host_wdata;
    mem_byte_en <= loader_byte_en when loader_active = '1' else (others => '1');

    loader_ready  <= mem_ready when loader_active = '1' else '0';
    loader_rvalid <= mem_rvalid when loader_active = '1' else '0';
    loader_rdata  <= mem_rdata;

    buf_addr <= tile_wr_addr when loader_active = '1' else tb_tile_addr;

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

    u_loader : entity work.tile_loader
        generic map (
            TILE_SIZE        => TILE_SIZE,
            ELEMENT_WIDTH    => ELEMENT_WIDTH,
            SDRAM_DATA_WIDTH => SDRAM_DATA_WIDTH,
            SDRAM_ADDR_WIDTH => SDRAM_ADDR_WIDTH
        )
        port map (
            clk           => clk,
            rst           => rst,
            start         => loader_start,
            base_addr     => to_unsigned(0, SDRAM_ADDR_WIDTH),
            row_stride    => to_unsigned(4, SDRAM_ADDR_WIDTH),
            busy          => loader_busy,
            done          => loader_done,
            sdram_req     => loader_req,
            sdram_we      => loader_we,
            sdram_addr    => loader_addr,
            sdram_wdata   => loader_wdata,
            sdram_byte_en => loader_byte_en,
            sdram_ready   => loader_ready,
            sdram_rvalid  => loader_rvalid,
            sdram_rdata   => loader_rdata,
            tile_wr_en    => tile_wr_en,
            tile_wr_addr  => tile_wr_addr,
            tile_wr_data  => tile_wr_data
        );

    u_buffer : entity work.tile_buffer_m10k
        generic map (
            ELEMENT_WIDTH => ELEMENT_WIDTH,
            ADDR_WIDTH    => TILE_ADDR_WIDTH,
            DEPTH         => 8
        )
        port map (
            clk     => clk,
            wr_en   => tile_wr_en,
            addr    => buf_addr,
            wr_data => tile_wr_data,
            rd_data => buf_rd_data
        );

    stim_proc : process
        variable expected : integer;
    begin
        rst <= '1';
        wait for 3 * CLK_PERIOD;
        rst <= '0';
        wait until rising_edge(clk);

        for addr_idx in 0 to 15 loop
            host_addr  <= to_unsigned(addr_idx, SDRAM_ADDR_WIDTH);
            host_wdata <= std_logic_vector(to_signed(addr_idx + 1, SDRAM_DATA_WIDTH));
            host_we    <= '1';
            host_req   <= '1';
            wait until rising_edge(clk);
            host_req <= '0';
            host_we  <= '0';
            wait until rising_edge(clk);
        end loop;

        loader_start <= '1';
        wait until rising_edge(clk);
        loader_start <= '0';

        for cycle_idx in 0 to 100 loop
            wait until rising_edge(clk);
            exit when loader_done = '1';
        end loop;

        assert loader_done = '1'
            report "tile_loader nao finalizou."
            severity failure;

        for idx in 0 to 3 loop
            tb_tile_addr <= to_unsigned(idx, TILE_ADDR_WIDTH);
            wait until rising_edge(clk);
            wait for 1 ns;

            if idx < 2 then
                expected := idx + 1;
            else
                expected := idx + 3;
            end if;

            assert buf_rd_data = to_signed(expected, ELEMENT_WIDTH)
                report "tile_loader carregou valor incorreto no tile."
                severity failure;
        end loop;

        report "SIM_RESULT: PASS" severity note;
        finish;
    end process;

end architecture sim;
