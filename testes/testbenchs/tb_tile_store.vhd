library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

library work;
use work.matrix_tiled_pkg.all;

entity tb_tile_store is
end entity tb_tile_store;

architecture sim of tb_tile_store is

    constant CLK_PERIOD       : time := 10 ns;
    constant N                : positive := 4;
    constant TILE_SIZE        : positive := 2;
    constant ACC_WIDTH        : positive := 32;
    constant SDRAM_DATA_WIDTH : positive := 32;
    constant SDRAM_ADDR_WIDTH : positive := 8;
    constant TILE_IDX_WIDTH   : positive := clog2((N / TILE_SIZE) + 1);

    signal clk : std_logic := '0';
    signal rst : std_logic := '0';

    signal store_start  : std_logic := '0';
    signal store_tile_i : unsigned(TILE_IDX_WIDTH-1 downto 0) := (others => '0');
    signal store_tile_j : unsigned(TILE_IDX_WIDTH-1 downto 0) := (others => '0');
    signal store_busy   : std_logic;
    signal store_done   : std_logic;

    signal store_wr_req   : std_logic;
    signal store_wr_addr  : unsigned(SDRAM_ADDR_WIDTH-1 downto 0);
    signal store_wr_data  : std_logic_vector(SDRAM_DATA_WIDTH-1 downto 0);
    signal store_wr_ready : std_logic;
    signal store_sdram_busy : std_logic;

    signal host_rd_req   : std_logic := '0';
    signal host_rd_addr  : unsigned(SDRAM_ADDR_WIDTH-1 downto 0) := (others => '0');
    signal host_rd_data  : std_logic_vector(SDRAM_DATA_WIDTH-1 downto 0);
    signal host_rd_valid : std_logic;

    signal mem_rd_req   : std_logic;
    signal mem_rd_addr  : unsigned(SDRAM_ADDR_WIDTH-1 downto 0);
    signal mem_rd_data  : std_logic_vector(SDRAM_DATA_WIDTH-1 downto 0);
    signal mem_rd_valid : std_logic;
    signal mem_rd_ready : std_logic;
    signal mem_wr_req   : std_logic;
    signal mem_wr_addr  : unsigned(SDRAM_ADDR_WIDTH-1 downto 0);
    signal mem_wr_data  : std_logic_vector(SDRAM_DATA_WIDTH-1 downto 0);
    signal mem_wr_ready : std_logic;
    signal mem_busy     : std_logic;

    signal tile_buf_wr_en   : std_logic := '0';
    signal tile_buf_row     : unsigned(clog2(TILE_SIZE)-1 downto 0) := (others => '0');
    signal tile_buf_col     : unsigned(clog2(TILE_SIZE)-1 downto 0) := (others => '0');
    signal tile_buf_wr_data : signed(ACC_WIDTH-1 downto 0) := (others => '0');
    signal tile_buf_rd_data : signed(ACC_WIDTH-1 downto 0);
    signal tile_buf_addr_dbg : unsigned(clog2(TILE_SIZE*TILE_SIZE)-1 downto 0);

    signal store_buf_row : unsigned(clog2(TILE_SIZE)-1 downto 0);
    signal store_buf_col : unsigned(clog2(TILE_SIZE)-1 downto 0);

    signal tb_buf_row : unsigned(clog2(TILE_SIZE)-1 downto 0) := (others => '0');
    signal tb_buf_col : unsigned(clog2(TILE_SIZE)-1 downto 0) := (others => '0');

    signal store_active : std_logic;

    function tile_value(
        constant local_row : natural;
        constant local_col : natural
    ) return natural is
    begin
        return 1000 + (local_row * 10) + local_col;
    end function;

    function c_addr(
        constant tile_i    : natural;
        constant tile_j    : natural;
        constant local_row : natural;
        constant local_col : natural
    ) return natural is
        variable global_row : natural;
        variable global_col : natural;
    begin
        global_row := (tile_i * TILE_SIZE) + local_row;
        global_col := (tile_j * TILE_SIZE) + local_col;
        return (global_row * N) + global_col;
    end function;

begin

    clk <= not clk after CLK_PERIOD / 2;

    store_active <= store_busy or store_start;

    mem_rd_req  <= '0' when store_active = '1' else host_rd_req;
    mem_rd_addr <= (others => '0') when store_active = '1' else host_rd_addr;
    mem_wr_req  <= store_wr_req when store_active = '1' else '0';
    mem_wr_addr <= store_wr_addr when store_active = '1' else (others => '0');
    mem_wr_data <= store_wr_data when store_active = '1' else (others => '0');

    store_wr_ready   <= mem_wr_ready when store_active = '1' else '0';
    store_sdram_busy <= mem_busy;
    host_rd_data     <= mem_rd_data;
    host_rd_valid    <= mem_rd_valid when store_active = '0' else '0';

    tile_buf_row <= store_buf_row when store_active = '1' else tb_buf_row;
    tile_buf_col <= store_buf_col when store_active = '1' else tb_buf_col;

    u_mem : entity work.sdram_model
        generic map (
            DATA_WIDTH    => SDRAM_DATA_WIDTH,
            ADDR_WIDTH    => SDRAM_ADDR_WIDTH,
            READ_LATENCY  => 1,
            WRITE_LATENCY => 1,
            DEPTH         => 256
        )
        port map (
            clk      => clk,
            rst      => rst,
            rd_req   => mem_rd_req,
            rd_addr  => mem_rd_addr,
            rd_data  => mem_rd_data,
            rd_valid => mem_rd_valid,
            rd_ready => mem_rd_ready,
            wr_req   => mem_wr_req,
            wr_addr  => mem_wr_addr,
            wr_data  => mem_wr_data,
            wr_ready => mem_wr_ready,
            busy     => mem_busy
        );

    u_buffer : entity work.tile_buffer_m10k
        generic map (
            TILE_SIZE     => TILE_SIZE,
            DATA_WIDTH    => 8,
            ACC_WIDTH     => ACC_WIDTH,
            USE_M10K      => true,
            IS_ACC_BUFFER => true,
            BUFFER_IMPL   => "INFERRED"
        )
        port map (
            clk            => clk,
            rst            => rst,
            wr_en          => tile_buf_wr_en,
            local_row      => tile_buf_row,
            local_col      => tile_buf_col,
            wr_data        => tile_buf_wr_data,
            rd_data        => tile_buf_rd_data,
            local_addr_dbg => tile_buf_addr_dbg
        );

    u_store : entity work.tile_store
        generic map (
            N                => N,
            TILE_SIZE        => TILE_SIZE,
            ACC_WIDTH        => ACC_WIDTH,
            SDRAM_DATA_WIDTH => SDRAM_DATA_WIDTH,
            SDRAM_ADDR_WIDTH => SDRAM_ADDR_WIDTH
        )
        port map (
            clk              => clk,
            rst              => rst,
            start            => store_start,
            tile_i           => store_tile_i,
            tile_j           => store_tile_j,
            busy             => store_busy,
            done             => store_done,
            sdram_wr_req     => store_wr_req,
            sdram_wr_addr    => store_wr_addr,
            sdram_wr_data    => store_wr_data,
            sdram_wr_ready   => store_wr_ready,
            sdram_busy       => store_sdram_busy,
            tile_c_local_row => store_buf_row,
            tile_c_local_col => store_buf_col,
            tile_c_rd_data   => tile_buf_rd_data
        );

    stim_proc : process
        variable expected_addr : natural;
        variable expected_val  : natural;
    begin
        rst <= '1';
        wait for 3 * CLK_PERIOD;
        rst <= '0';
        wait until rising_edge(clk);

        for row_idx in 0 to TILE_SIZE-1 loop
            for col_idx in 0 to TILE_SIZE-1 loop
                tb_buf_row       <= to_unsigned(row_idx, tb_buf_row'length);
                tb_buf_col       <= to_unsigned(col_idx, tb_buf_col'length);
                tile_buf_wr_data <= to_signed(tile_value(row_idx, col_idx), ACC_WIDTH);
                tile_buf_wr_en   <= '1';
                wait until rising_edge(clk);
                tile_buf_wr_en <= '0';
                wait until rising_edge(clk);

                assert to_integer(tile_buf_addr_dbg) = (row_idx * TILE_SIZE) + col_idx
                    report "Endereco local do tile_C incorreto no preload."
                    severity failure;
            end loop;
        end loop;

        store_tile_i <= to_unsigned(1, store_tile_i'length);
        store_tile_j <= to_unsigned(1, store_tile_j'length);
        store_start  <= '1';
        wait until rising_edge(clk);
        store_start <= '0';

        for cycle_idx in 0 to 200 loop
            wait until rising_edge(clk);
            exit when store_done = '1';
        end loop;

        assert store_done = '1'
            report "tile_store nao finalizou."
            severity failure;

        wait until rising_edge(clk);

        for row_idx in 0 to TILE_SIZE-1 loop
            for col_idx in 0 to TILE_SIZE-1 loop
                expected_addr := c_addr(1, 1, row_idx, col_idx);
                expected_val  := tile_value(row_idx, col_idx);

                host_rd_addr <= to_unsigned(expected_addr, SDRAM_ADDR_WIDTH);
                host_rd_req  <= '1';
                wait until rising_edge(clk);
                host_rd_req <= '0';

                for cycle_idx in 0 to 20 loop
                    wait until rising_edge(clk);
                    wait for 1 ns;
                    exit when host_rd_valid = '1';
                end loop;

                assert host_rd_valid = '1'
                    report "Leitura da SDRAM nao retornou rd_valid."
                    severity failure;

                assert host_rd_data = std_logic_vector(to_signed(expected_val, SDRAM_DATA_WIDTH))
                    report "tile_store gravou valor incorreto na SDRAM."
                    severity failure;
            end loop;
        end loop;

        report "SIM_RESULT: PASS" severity note;
        finish;
    end process;

end architecture sim;
