library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_perf_counters is
end entity tb_perf_counters;

architecture sim of tb_perf_counters is

    constant CLK_PERIOD : time := 10 ns;

    signal clk : std_logic := '0';
    signal rst : std_logic := '0';
    signal clear : std_logic := '0';
    signal enable : std_logic := '0';
    signal event_sdram_read : std_logic := '0';
    signal event_sdram_write : std_logic := '0';
    signal event_mac_group : std_logic := '0';
    signal cycles : unsigned(15 downto 0);
    signal reads : unsigned(15 downto 0);
    signal writes : unsigned(15 downto 0);
    signal mac_groups : unsigned(15 downto 0);

begin

    clk <= not clk after CLK_PERIOD / 2;

    dut : entity work.perf_counters
        generic map (
            COUNTER_WIDTH => 16
        )
        port map (
            clk               => clk,
            rst               => rst,
            clear             => clear,
            enable            => enable,
            event_sdram_read  => event_sdram_read,
            event_sdram_write => event_sdram_write,
            event_mac_group   => event_mac_group,
            cycle_count       => cycles,
            sdram_read_count  => reads,
            sdram_write_count => writes,
            mac_group_count   => mac_groups
        );

    stim_proc : process
    begin
        rst <= '1';
        wait for 3 * CLK_PERIOD;
        rst <= '0';

        enable <= '1';
        event_sdram_read <= '1';
        wait until rising_edge(clk);
        event_sdram_read <= '0';
        event_sdram_write <= '1';
        event_mac_group <= '1';
        wait until rising_edge(clk);
        event_sdram_write <= '0';
        event_mac_group <= '0';
        wait until rising_edge(clk);
        enable <= '0';
        wait for 1 ns;

        assert cycles = to_unsigned(3, 16)
            report "cycle_count incorreto."
            severity failure;

        assert reads = to_unsigned(1, 16) and writes = to_unsigned(1, 16) and mac_groups = to_unsigned(1, 16)
            report "Contadores de eventos incorretos."
            severity failure;

        report "SIM_RESULT: PASS" severity note;
        finish;
    end process;

end architecture sim;
