library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_accelerator_controller is
end entity tb_accelerator_controller;

architecture sim of tb_accelerator_controller is

    constant CLK_PERIOD       : time := 10 ns;
    constant N                : positive := 4;
    constant TILE_SIZE        : positive := 2;
    constant NUM_MACS         : positive := 2;
    constant DATA_WIDTH       : positive := 8;
    constant ACC_WIDTH        : positive := 32;
    constant SDRAM_DATA_WIDTH : positive := 32;
    constant SDRAM_ADDR_WIDTH : positive := 8;
    constant MATRIX_ELEMS     : natural := N * N;
    constant A_BASE           : natural := 0;
    constant B_BASE           : natural := MATRIX_ELEMS;
    constant C_BASE           : natural := MATRIX_ELEMS * 2;

    signal clk : std_logic := '0';
    signal rst : std_logic := '0';

    signal start : std_logic := '0';
    signal busy  : std_logic;
    signal done  : std_logic;

    signal ctrl_rd_req   : std_logic;
    signal ctrl_rd_addr  : unsigned(SDRAM_ADDR_WIDTH-1 downto 0);
    signal ctrl_rd_data  : std_logic_vector(SDRAM_DATA_WIDTH-1 downto 0);
    signal ctrl_rd_valid : std_logic;
    signal ctrl_rd_ready : std_logic;
    signal ctrl_wr_req   : std_logic;
    signal ctrl_wr_addr  : unsigned(SDRAM_ADDR_WIDTH-1 downto 0);
    signal ctrl_wr_data  : std_logic_vector(SDRAM_DATA_WIDTH-1 downto 0);
    signal ctrl_wr_ready : std_logic;
    signal ctrl_sdram_busy : std_logic;

    signal host_rd_req   : std_logic := '0';
    signal host_rd_addr  : unsigned(SDRAM_ADDR_WIDTH-1 downto 0) := (others => '0');
    signal host_rd_data  : std_logic_vector(SDRAM_DATA_WIDTH-1 downto 0);
    signal host_rd_valid : std_logic;
    signal host_wr_req   : std_logic := '0';
    signal host_wr_addr  : unsigned(SDRAM_ADDR_WIDTH-1 downto 0) := (others => '0');
    signal host_wr_data  : std_logic_vector(SDRAM_DATA_WIDTH-1 downto 0) := (others => '0');

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

    signal ctrl_active : std_logic;
    signal event_read  : std_logic;
    signal event_write : std_logic;
    signal event_mac   : std_logic;
    signal perf_total_cycles        : unsigned(63 downto 0);
    signal perf_load_cycles         : unsigned(63 downto 0);
    signal perf_compute_cycles      : unsigned(63 downto 0);
    signal perf_store_cycles        : unsigned(63 downto 0);
    signal perf_num_tiles_processed : unsigned(63 downto 0);
    signal perf_num_mac_ops_issued  : unsigned(63 downto 0);

    function a_value(row_idx : natural; col_idx : natural) return integer is
    begin
        return (row_idx + (2 * col_idx) + 1) mod 8;
    end function;

    function b_value(row_idx : natural; col_idx : natural) return integer is
    begin
        return ((3 * row_idx) + col_idx + 2) mod 8;
    end function;

    function c_expected(row_idx : natural; col_idx : natural) return integer is
        variable acc : integer := 0;
    begin
        for k in 0 to N-1 loop
            acc := acc + a_value(row_idx, k) * b_value(k, col_idx);
        end loop;

        return acc;
    end function;

begin

    clk <= not clk after CLK_PERIOD / 2;

    ctrl_active <= busy or start;

    mem_rd_req  <= ctrl_rd_req when ctrl_active = '1' else host_rd_req;
    mem_rd_addr <= ctrl_rd_addr when ctrl_active = '1' else host_rd_addr;
    mem_wr_req  <= ctrl_wr_req when ctrl_active = '1' else host_wr_req;
    mem_wr_addr <= ctrl_wr_addr when ctrl_active = '1' else host_wr_addr;
    mem_wr_data <= ctrl_wr_data when ctrl_active = '1' else host_wr_data;

    ctrl_rd_ready <= mem_rd_ready when ctrl_active = '1' else '0';
    ctrl_rd_valid <= mem_rd_valid when ctrl_active = '1' else '0';
    ctrl_rd_data  <= mem_rd_data;
    ctrl_wr_ready <= mem_wr_ready when ctrl_active = '1' else '0';
    ctrl_sdram_busy <= mem_busy when ctrl_active = '1' else '1';

    host_rd_valid <= mem_rd_valid when ctrl_active = '0' else '0';
    host_rd_data  <= mem_rd_data;

    u_controller : entity work.accelerator_controller
        generic map (
            N                => N,
            TILE_SIZE        => TILE_SIZE,
            NUM_MACS         => NUM_MACS,
            DATA_WIDTH       => DATA_WIDTH,
            ACC_WIDTH        => ACC_WIDTH,
            SDRAM_DATA_WIDTH => SDRAM_DATA_WIDTH,
            SDRAM_ADDR_WIDTH => SDRAM_ADDR_WIDTH
        )
        port map (
            clk               => clk,
            rst               => rst,
            start             => start,
            busy              => busy,
            done              => done,
            sdram_rd_req      => ctrl_rd_req,
            sdram_rd_addr     => ctrl_rd_addr,
            sdram_rd_data     => ctrl_rd_data,
            sdram_rd_valid    => ctrl_rd_valid,
            sdram_rd_ready    => ctrl_rd_ready,
            sdram_wr_req      => ctrl_wr_req,
            sdram_wr_addr     => ctrl_wr_addr,
            sdram_wr_data     => ctrl_wr_data,
            sdram_wr_ready    => ctrl_wr_ready,
            sdram_busy        => ctrl_sdram_busy,
            event_sdram_read  => event_read,
            event_sdram_write => event_write,
            event_mac_group   => event_mac,
            perf_total_cycles        => perf_total_cycles,
            perf_load_cycles         => perf_load_cycles,
            perf_compute_cycles      => perf_compute_cycles,
            perf_store_cycles        => perf_store_cycles,
            perf_num_tiles_processed => perf_num_tiles_processed,
            perf_num_mac_ops_issued  => perf_num_mac_ops_issued,
            status_load_active       => open,
            status_compute_active    => open,
            status_store_active      => open,
            status_tile_done         => open
        );

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

    stim_proc : process
        variable addr : natural;
        variable exec_cycles : natural := 0;
    begin
        rst <= '1';
        wait for 3 * CLK_PERIOD;
        rst <= '0';
        wait until rising_edge(clk);

        for row_idx in 0 to N-1 loop
            for col_idx in 0 to N-1 loop
                addr := row_idx * N + col_idx;

                host_wr_addr <= to_unsigned(A_BASE + addr, SDRAM_ADDR_WIDTH);
                host_wr_data <= std_logic_vector(to_signed(a_value(row_idx, col_idx), SDRAM_DATA_WIDTH));
                host_wr_req  <= '1';
                wait until rising_edge(clk);
                host_wr_req <= '0';
                loop
                    wait until rising_edge(clk);
                    exit when mem_wr_ready = '1';
                end loop;

                host_wr_addr <= to_unsigned(B_BASE + addr, SDRAM_ADDR_WIDTH);
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

        start <= '1';
        wait until rising_edge(clk);
        start <= '0';

        for cycle_idx in 0 to 5000 loop
            wait until rising_edge(clk);
            exec_cycles := exec_cycles + 1;
            exit when done = '1';
        end loop;

        assert done = '1'
            report "accelerator_controller nao finalizou."
            severity failure;

        report "Ciclos de execucao: " & integer'image(exec_cycles) severity note;

        assert perf_total_cycles > 0
            report "perf_total_cycles nao foi atualizado."
            severity failure;

        assert perf_load_cycles > 0
            report "perf_load_cycles nao foi atualizado."
            severity failure;

        assert perf_compute_cycles > 0
            report "perf_compute_cycles nao foi atualizado."
            severity failure;

        assert perf_store_cycles > 0
            report "perf_store_cycles nao foi atualizado."
            severity failure;

        assert perf_num_tiles_processed = to_unsigned((N / TILE_SIZE) * (N / TILE_SIZE), 64)
            report "perf_num_tiles_processed incorreto."
            severity failure;

        assert perf_num_mac_ops_issued = to_unsigned(N * N * N, 64)
            report "perf_num_mac_ops_issued incorreto."
            severity failure;

        for row_idx in 0 to N-1 loop
            for col_idx in 0 to N-1 loop
                addr := row_idx * N + col_idx;
                host_rd_addr <= to_unsigned(C_BASE + addr, SDRAM_ADDR_WIDTH);
                host_rd_req  <= '1';
                wait until rising_edge(clk);
                host_rd_req <= '0';

                loop
                    wait until rising_edge(clk);
                    exit when host_rd_valid = '1';
                end loop;

                assert signed(host_rd_data) = to_signed(c_expected(row_idx, col_idx), SDRAM_DATA_WIDTH)
                    report "Resultado incorreto no accelerator_controller."
                    severity failure;
            end loop;
        end loop;

        report "SIM_RESULT: PASS" severity note;
        finish;
    end process;

end architecture sim;
