library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

library work;
use work.matrix_tiled_pkg.all;

entity tb_tile_loader is
end entity tb_tile_loader;

architecture sim of tb_tile_loader is

    constant CLK_PERIOD       : time := 10 ns;
    constant N                : positive := 4;
    constant TILE_SIZE        : positive := 2;
    constant DATA_WIDTH       : positive := 8;
    constant ACC_WIDTH        : positive := 32;
    constant SDRAM_DATA_WIDTH : positive := 32;
    constant SDRAM_ADDR_WIDTH : positive := 8;
    constant TILE_INDEX_WIDTH : positive := clog2((N / TILE_SIZE) + 1);

    constant BASE_A : natural := 0;
    constant BASE_B : natural := N * N;

    signal clk : std_logic := '0';
    signal rst : std_logic := '0';

    signal loader_start : std_logic := '0';
    signal tile_i : unsigned(TILE_INDEX_WIDTH-1 downto 0) := (others => '0');
    signal tile_j : unsigned(TILE_INDEX_WIDTH-1 downto 0) := (others => '0');
    signal tile_k : unsigned(TILE_INDEX_WIDTH-1 downto 0) := (others => '0');
    signal loader_busy : std_logic;
    signal loader_done : std_logic;

    signal loader_rd_req   : std_logic;
    signal loader_rd_addr  : unsigned(SDRAM_ADDR_WIDTH-1 downto 0);
    signal loader_rd_data  : std_logic_vector(SDRAM_DATA_WIDTH-1 downto 0);
    signal loader_rd_valid : std_logic;
    signal loader_rd_ready : std_logic;
    signal loader_sdram_busy : std_logic;

    signal host_wr_req  : std_logic := '0';
    signal host_wr_addr : unsigned(SDRAM_ADDR_WIDTH-1 downto 0) := (others => '0');
    signal host_wr_data : std_logic_vector(SDRAM_DATA_WIDTH-1 downto 0) := (others => '0');

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

    signal tile_a_wr_en  : std_logic;
    signal tile_a_row_wr : unsigned(clog2(TILE_SIZE)-1 downto 0);
    signal tile_a_col_wr : unsigned(clog2(TILE_SIZE)-1 downto 0);
    signal tile_a_data   : signed(DATA_WIDTH-1 downto 0);

    signal tile_b_wr_en  : std_logic;
    signal tile_b_row_wr : unsigned(clog2(TILE_SIZE)-1 downto 0);
    signal tile_b_col_wr : unsigned(clog2(TILE_SIZE)-1 downto 0);
    signal tile_b_data   : signed(DATA_WIDTH-1 downto 0);

    signal tb_row : unsigned(clog2(TILE_SIZE)-1 downto 0) := (others => '0');
    signal tb_col : unsigned(clog2(TILE_SIZE)-1 downto 0) := (others => '0');

    signal buf_a_row : unsigned(clog2(TILE_SIZE)-1 downto 0) := (others => '0');
    signal buf_a_col : unsigned(clog2(TILE_SIZE)-1 downto 0) := (others => '0');
    signal buf_b_row : unsigned(clog2(TILE_SIZE)-1 downto 0) := (others => '0');
    signal buf_b_col : unsigned(clog2(TILE_SIZE)-1 downto 0) := (others => '0');

    signal buf_a_addr_dbg : unsigned(clog2(TILE_SIZE*TILE_SIZE)-1 downto 0);
    signal buf_b_addr_dbg : unsigned(clog2(TILE_SIZE*TILE_SIZE)-1 downto 0);
    signal buf_a_rd_data  : signed(DATA_WIDTH-1 downto 0);
    signal buf_b_rd_data  : signed(DATA_WIDTH-1 downto 0);

    signal loader_active : std_logic;

    function a_value(row_idx : natural; col_idx : natural) return integer is
    begin
        return 1 + (row_idx * 10) + col_idx;
    end function;

    function b_value(row_idx : natural; col_idx : natural) return integer is
    begin
        return 50 + (row_idx * 10) + col_idx;
    end function;

    function row_major_addr(
        constant base    : natural;
        constant row_idx : natural;
        constant col_idx : natural
    ) return natural is
    begin
        return base + (row_idx * N) + col_idx;
    end function;

begin

    clk <= not clk after CLK_PERIOD / 2;

    loader_active <= '1' when loader_busy = '1' or loader_start = '1' or
                              tile_a_wr_en = '1' or tile_b_wr_en = '1'
                     else '0';

    mem_rd_req  <= loader_rd_req when loader_active = '1' else '0';
    mem_rd_addr <= loader_rd_addr when loader_active = '1' else (others => '0');
    mem_wr_req  <= '0' when loader_active = '1' else host_wr_req;
    mem_wr_addr <= (others => '0') when loader_active = '1' else host_wr_addr;
    mem_wr_data <= (others => '0') when loader_active = '1' else host_wr_data;

    loader_rd_ready <= mem_rd_ready when loader_active = '1' else '0';
    loader_rd_valid <= mem_rd_valid when loader_active = '1' else '0';
    loader_rd_data  <= mem_rd_data;
    loader_sdram_busy <= mem_busy;

    buf_a_row <= tile_a_row_wr when loader_active = '1' else tb_row;
    buf_a_col <= tile_a_col_wr when loader_active = '1' else tb_col;
    buf_b_row <= tile_b_row_wr when loader_active = '1' else tb_row;
    buf_b_col <= tile_b_col_wr when loader_active = '1' else tb_col;

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

    dut : entity work.tile_loader
        generic map (
            N                => N,
            TILE_SIZE        => TILE_SIZE,
            DATA_WIDTH       => DATA_WIDTH,
            SDRAM_DATA_WIDTH => SDRAM_DATA_WIDTH,
            SDRAM_ADDR_WIDTH => SDRAM_ADDR_WIDTH
        )
        port map (
            clk              => clk,
            rst              => rst,
            start            => loader_start,
            tile_i           => tile_i,
            tile_j           => tile_j,
            tile_k           => tile_k,
            busy             => loader_busy,
            done             => loader_done,
            sdram_rd_req     => loader_rd_req,
            sdram_rd_addr    => loader_rd_addr,
            sdram_rd_data    => loader_rd_data,
            sdram_rd_valid   => loader_rd_valid,
            sdram_rd_ready   => loader_rd_ready,
            sdram_busy       => loader_sdram_busy,
            tile_a_wr_en     => tile_a_wr_en,
            tile_a_local_row => tile_a_row_wr,
            tile_a_local_col => tile_a_col_wr,
            tile_a_wr_data   => tile_a_data,
            tile_b_wr_en     => tile_b_wr_en,
            tile_b_local_row => tile_b_row_wr,
            tile_b_local_col => tile_b_col_wr,
            tile_b_wr_data   => tile_b_data
        );

    u_buf_a : entity work.tile_buffer_m10k
        generic map (
            TILE_SIZE     => TILE_SIZE,
            DATA_WIDTH    => DATA_WIDTH,
            ACC_WIDTH     => ACC_WIDTH,
            USE_M10K      => true,
            IS_ACC_BUFFER => false,
            BUFFER_IMPL   => "INFERRED"
        )
        port map (
            clk            => clk,
            rst            => rst,
            wr_en          => tile_a_wr_en,
            local_row      => buf_a_row,
            local_col      => buf_a_col,
            wr_data        => tile_a_data,
            rd_data        => buf_a_rd_data,
            local_addr_dbg => buf_a_addr_dbg
        );

    u_buf_b : entity work.tile_buffer_m10k
        generic map (
            TILE_SIZE     => TILE_SIZE,
            DATA_WIDTH    => DATA_WIDTH,
            ACC_WIDTH     => ACC_WIDTH,
            USE_M10K      => true,
            IS_ACC_BUFFER => false,
            BUFFER_IMPL   => "INFERRED"
        )
        port map (
            clk            => clk,
            rst            => rst,
            wr_en          => tile_b_wr_en,
            local_row      => buf_b_row,
            local_col      => buf_b_col,
            wr_data        => tile_b_data,
            rd_data        => buf_b_rd_data,
            local_addr_dbg => buf_b_addr_dbg
        );

    stim_proc : process
        variable expected_a : integer;
        variable expected_b : integer;
    begin
        rst <= '1';
        wait for 3 * CLK_PERIOD;
        rst <= '0';
        wait until rising_edge(clk);

        for row_idx in 0 to N-1 loop
            for col_idx in 0 to N-1 loop
                host_wr_addr <= to_unsigned(row_major_addr(BASE_A, row_idx, col_idx), SDRAM_ADDR_WIDTH);
                host_wr_data <= std_logic_vector(to_signed(a_value(row_idx, col_idx), SDRAM_DATA_WIDTH));
                host_wr_req  <= '1';
                wait until rising_edge(clk);
                host_wr_req <= '0';

                loop
                    wait until rising_edge(clk);
                    exit when mem_wr_ready = '1';
                end loop;

                host_wr_addr <= to_unsigned(row_major_addr(BASE_B, row_idx, col_idx), SDRAM_ADDR_WIDTH);
                host_wr_data <= std_logic_vector(to_signed(b_value(row_idx, col_idx), SDRAM_DATA_WIDTH));
                host_wr_req  <= '1';
                wait until rising_edge(clk);
                host_wr_req <= '0';

                loop
                    wait until rising_edge(clk);
                    exit when mem_wr_ready = '1';
                end loop;
            end loop;
        end loop;

        tile_i <= to_unsigned(0, tile_i'length);
        tile_j <= to_unsigned(0, tile_j'length);
        tile_k <= to_unsigned(0, tile_k'length);

        loader_start <= '1';
        wait until rising_edge(clk);
        loader_start <= '0';

        for cycle_idx in 0 to 200 loop
            wait until rising_edge(clk);
            exit when loader_done = '1';
        end loop;

        assert loader_done = '1'
            report "tile_loader nao finalizou."
            severity failure;

        for local_row in 0 to TILE_SIZE-1 loop
            for local_col in 0 to TILE_SIZE-1 loop
                tb_row <= to_unsigned(local_row, tb_row'length);
                tb_col <= to_unsigned(local_col, tb_col'length);
                wait until rising_edge(clk);
                wait for 1 ns;

                expected_a := a_value(local_row, local_col);
                expected_b := b_value(local_row, local_col);

                assert buf_a_addr_dbg = to_unsigned((local_row * TILE_SIZE) + local_col, buf_a_addr_dbg'length)
                    report "Endereco local A incorreto."
                    severity failure;

                assert buf_b_addr_dbg = to_unsigned((local_row * TILE_SIZE) + local_col, buf_b_addr_dbg'length)
                    report "Endereco local B incorreto."
                    severity failure;

                assert buf_a_rd_data = to_signed(expected_a, DATA_WIDTH)
                    report "A_tile valor incorreto em local(" &
                           integer'image(local_row) & "," & integer'image(local_col) & ")."
                    severity failure;

                assert buf_b_rd_data = to_signed(expected_b, DATA_WIDTH)
                    report "B_tile valor incorreto em local(" &
                           integer'image(local_row) & "," & integer'image(local_col) & ")."
                    severity failure;
            end loop;
        end loop;

        report "SIM_RESULT: PASS" severity note;
        finish;
    end process;

end architecture sim;
