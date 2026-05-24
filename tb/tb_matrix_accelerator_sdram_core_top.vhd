library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_matrix_accelerator_sdram_core_top is
end entity tb_matrix_accelerator_sdram_core_top;

architecture sim of tb_matrix_accelerator_sdram_core_top is

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

    signal host_req     : std_logic := '0';
    signal host_we      : std_logic := '0';
    signal host_addr    : unsigned(SDRAM_ADDR_WIDTH-1 downto 0) := (others => '0');
    signal host_wdata   : std_logic_vector(SDRAM_DATA_WIDTH-1 downto 0) := (others => '0');
    signal host_byte_en : std_logic_vector((SDRAM_DATA_WIDTH/8)-1 downto 0) := (others => '1');
    signal host_ready   : std_logic;
    signal host_rvalid  : std_logic;
    signal host_rdata   : std_logic_vector(SDRAM_DATA_WIDTH-1 downto 0);

    signal start : std_logic := '0';
    signal busy  : std_logic;
    signal done  : std_logic;

    signal perf_cycles       : unsigned(63 downto 0);
    signal perf_sdram_reads  : unsigned(63 downto 0);
    signal perf_sdram_writes : unsigned(63 downto 0);
    signal perf_mac_groups   : unsigned(63 downto 0);

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

    dut : entity work.matrix_accelerator_sdram_core_top
        generic map (
            N                => N,
            TILE_SIZE        => TILE_SIZE,
            NUM_MACS         => NUM_MACS,
            DATA_WIDTH       => DATA_WIDTH,
            ACC_WIDTH        => ACC_WIDTH,
            SDRAM_DATA_WIDTH => SDRAM_DATA_WIDTH,
            SDRAM_ADDR_WIDTH => SDRAM_ADDR_WIDTH,
            SDRAM_DEPTH      => 256,
            USE_SIM_SDRAM    => true
        )
        port map (
            clk               => clk,
            rst               => rst,
            host_req          => host_req,
            host_we           => host_we,
            host_addr         => host_addr,
            host_wdata        => host_wdata,
            host_byte_en      => host_byte_en,
            host_ready        => host_ready,
            host_rvalid       => host_rvalid,
            host_rdata        => host_rdata,
            start             => start,
            busy              => busy,
            done              => done,
            perf_cycles       => perf_cycles,
            perf_sdram_reads  => perf_sdram_reads,
            perf_sdram_writes => perf_sdram_writes,
            perf_mac_groups   => perf_mac_groups
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

                host_addr  <= to_unsigned(A_BASE + addr, SDRAM_ADDR_WIDTH);
                host_wdata <= std_logic_vector(to_signed(a_value(row_idx, col_idx), SDRAM_DATA_WIDTH));
                host_we    <= '1';
                host_req   <= '1';
                wait until rising_edge(clk);
                host_req <= '0';
                host_we  <= '0';
                wait until rising_edge(clk);

                host_addr  <= to_unsigned(B_BASE + addr, SDRAM_ADDR_WIDTH);
                host_wdata <= std_logic_vector(to_signed(b_value(row_idx, col_idx), SDRAM_DATA_WIDTH));
                host_we    <= '1';
                host_req   <= '1';
                wait until rising_edge(clk);
                host_req <= '0';
                host_we  <= '0';
                wait until rising_edge(clk);
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
            report "matrix_accelerator_sdram_core_top nao finalizou."
            severity failure;

        report "Ciclos de execucao: " & integer'image(exec_cycles) severity note;

        for row_idx in 0 to N-1 loop
            for col_idx in 0 to N-1 loop
                addr := row_idx * N + col_idx;
                host_addr <= to_unsigned(C_BASE + addr, SDRAM_ADDR_WIDTH);
                host_we   <= '0';
                host_req  <= '1';
                wait until rising_edge(clk);
                host_req <= '0';
                wait for 1 ns;

                assert host_rvalid = '1' and signed(host_rdata) = to_signed(c_expected(row_idx, col_idx), SDRAM_DATA_WIDTH)
                    report "Resultado incorreto no core top SDRAM."
                    severity failure;
            end loop;
        end loop;

        assert perf_cycles > 0 and perf_sdram_reads > 0 and perf_sdram_writes > 0 and perf_mac_groups > 0
            report "Contadores de performance nao foram atualizados."
            severity failure;

        report "SIM_RESULT: PASS" severity note;
        finish;
    end process;

end architecture sim;
