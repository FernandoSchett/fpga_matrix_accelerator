library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_perf_counters is
end entity tb_perf_counters;

architecture sim of tb_perf_counters is

    constant CLK_PERIOD   : time := 10 ns;
    constant COUNTER_WIDTH : positive := 16;

    signal clk : std_logic := '0';
    signal rst : std_logic := '0';

    signal start_count : std_logic := '0';
    signal stop_count  : std_logic := '0';
    signal load_active : std_logic := '0';
    signal compute_active : std_logic := '0';
    signal store_active : std_logic := '0';
    signal tile_done : std_logic := '0';
    signal mac_ops_issued : unsigned(COUNTER_WIDTH-1 downto 0) := (others => '0');

    signal total_cycles : unsigned(COUNTER_WIDTH-1 downto 0);
    signal load_cycles : unsigned(COUNTER_WIDTH-1 downto 0);
    signal compute_cycles : unsigned(COUNTER_WIDTH-1 downto 0);
    signal store_cycles : unsigned(COUNTER_WIDTH-1 downto 0);
    signal num_tiles_processed : unsigned(COUNTER_WIDTH-1 downto 0);
    signal num_mac_ops_issued : unsigned(COUNTER_WIDTH-1 downto 0);

begin

    clk <= not clk after CLK_PERIOD / 2;

    dut : entity work.perf_counters
        generic map (
            COUNTER_WIDTH => COUNTER_WIDTH
        )
        port map (
            clk                   => clk,
            rst                   => rst,
            start_count           => start_count,
            stop_count            => stop_count,
            load_active           => load_active,
            compute_active        => compute_active,
            store_active          => store_active,
            tile_done             => tile_done,
            mac_ops_issued        => mac_ops_issued,
            total_cycles          => total_cycles,
            load_cycles           => load_cycles,
            compute_cycles        => compute_cycles,
            store_cycles          => store_cycles,
            num_tiles_processed   => num_tiles_processed,
            num_mac_ops_issued    => num_mac_ops_issued
        );

    stim_proc : process
    begin
        rst <= '1';
        wait for 3 * CLK_PERIOD;
        rst <= '0';
        wait until rising_edge(clk);

        start_count <= '1';
        wait until rising_edge(clk);
        start_count <= '0';

        load_active <= '1';
        for cycle_idx in 0 to 2 loop
            wait until rising_edge(clk);
        end loop;
        load_active <= '0';

        wait until rising_edge(clk);

        compute_active <= '1';
        mac_ops_issued <= to_unsigned(4, COUNTER_WIDTH);
        for cycle_idx in 0 to 3 loop
            wait until rising_edge(clk);
        end loop;
        compute_active <= '0';
        mac_ops_issued <= (others => '0');

        store_active <= '1';
        wait until rising_edge(clk);
        tile_done <= '1';
        wait until rising_edge(clk);
        store_active <= '0';
        tile_done <= '0';

        stop_count <= '1';
        wait until rising_edge(clk);
        stop_count <= '0';
        wait for 1 ns;

        assert total_cycles = to_unsigned(11, COUNTER_WIDTH)
            report "total_cycles incorreto."
            severity failure;

        assert load_cycles = to_unsigned(3, COUNTER_WIDTH)
            report "load_cycles incorreto."
            severity failure;

        assert compute_cycles = to_unsigned(4, COUNTER_WIDTH)
            report "compute_cycles incorreto."
            severity failure;

        assert store_cycles = to_unsigned(2, COUNTER_WIDTH)
            report "store_cycles incorreto."
            severity failure;

        assert num_tiles_processed = to_unsigned(1, COUNTER_WIDTH)
            report "num_tiles_processed incorreto."
            severity failure;

        assert num_mac_ops_issued = to_unsigned(16, COUNTER_WIDTH)
            report "num_mac_ops_issued incorreto."
            severity failure;

        load_active <= '1';
        compute_active <= '1';
        store_active <= '1';
        mac_ops_issued <= to_unsigned(9, COUNTER_WIDTH);
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        load_active <= '0';
        compute_active <= '0';
        store_active <= '0';
        mac_ops_issued <= (others => '0');
        wait for 1 ns;

        assert total_cycles = to_unsigned(11, COUNTER_WIDTH)
            report "Contadores mudaram depois de stop_count."
            severity failure;

        start_count <= '1';
        wait until rising_edge(clk);
        start_count <= '0';
        wait for 1 ns;

        assert total_cycles = to_unsigned(0, COUNTER_WIDTH)
            report "start_count nao limpou total_cycles."
            severity failure;

        assert load_cycles = to_unsigned(0, COUNTER_WIDTH)
            report "start_count nao limpou load_cycles."
            severity failure;

        report "SIM_RESULT: PASS" severity note;
        finish;
    end process;

end architecture sim;
