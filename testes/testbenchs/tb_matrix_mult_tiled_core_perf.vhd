library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

library work;
use work.matrix_tiled_pkg.all;

entity tb_matrix_mult_tiled_core_perf is
    generic (
        N          : positive := 4;
        TILE_SIZE  : positive := 2;
        NUM_MACS   : positive := 2;
        DATA_WIDTH : positive := 8;
        ACC_WIDTH  : positive := 32
    );
end entity tb_matrix_mult_tiled_core_perf;

architecture sim of tb_matrix_mult_tiled_core_perf is

    constant CLK_PERIOD : time := 10 ns;
    constant ADDR_WIDTH : positive := clog2(N*N);

    signal clk : std_logic := '0';
    signal rst : std_logic := '0';

    signal wr_en      : std_logic := '0';
    signal matrix_sel : std_logic := '0';
    signal wr_addr    : unsigned(ADDR_WIDTH-1 downto 0) := (others => '0');
    signal data_in    : signed(DATA_WIDTH-1 downto 0) := (others => '0');

    signal start : std_logic := '0';
    signal busy  : std_logic;
    signal done  : std_logic;

    signal result_addr : unsigned(ADDR_WIDTH-1 downto 0) := (others => '0');
    signal data_out    : signed(ACC_WIDTH-1 downto 0);

begin

    clk <= not clk after CLK_PERIOD / 2;

    dut : entity work.matrix_mult_tiled_core
        generic map (
            N          => N,
            TILE_SIZE  => TILE_SIZE,
            NUM_MACS   => NUM_MACS,
            DATA_WIDTH => DATA_WIDTH,
            ACC_WIDTH  => ACC_WIDTH
        )
        port map (
            clk => clk,
            rst => rst,

            wr_en      => wr_en,
            matrix_sel => matrix_sel,
            wr_addr    => wr_addr,
            data_in    => data_in,

            start => start,
            busy  => busy,
            done  => done,

            result_addr => result_addr,
            data_out    => data_out
        );

    stim_proc : process
        variable exec_cycles : natural := 0;
        variable timeout_cycles : natural := 0;
    begin
        assert N mod TILE_SIZE = 0
            report "N precisa ser multiplo de TILE_SIZE para este testbench."
            severity failure;

        rst <= '1';
        wait for 3 * CLK_PERIOD;
        rst <= '0';
        wait for CLK_PERIOD;

        start <= '1';
        wait until rising_edge(clk);
        start <= '0';

        exec_cycles := 0;
        timeout_cycles := (N * N * N * 32) + 10000;

        loop
            wait until rising_edge(clk);
            exec_cycles := exec_cycles + 1;

            if done = '1' then
                exit;
            end if;

            assert exec_cycles < timeout_cycles
                report "Timeout medindo ciclos de execucao."
                severity failure;
        end loop;

        report "Ciclos de execucao: " & integer'image(exec_cycles) severity note;
        report "Teste perf tiled passou para N=" & integer'image(N) &
               ", TILE_SIZE=" & integer'image(TILE_SIZE) &
               ", NUM_MACS=" & integer'image(NUM_MACS) severity note;
        report "SIM_RESULT: PASS" severity note;

        finish;
    end process;

end architecture sim;
