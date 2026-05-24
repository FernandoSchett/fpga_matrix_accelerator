library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_tile_scheduler is
end entity tb_tile_scheduler;

architecture sim of tb_tile_scheduler is

    constant CLK_PERIOD : time := 10 ns;

    signal clk : std_logic := '0';
    signal rst : std_logic := '0';

    signal start   : std_logic := '0';
    signal advance : std_logic := '0';
    signal busy    : std_logic;
    signal valid   : std_logic;
    signal done    : std_logic;
    signal first_k : std_logic;
    signal tile_row : unsigned(1 downto 0);
    signal tile_col : unsigned(1 downto 0);
    signal tile_k   : unsigned(1 downto 0);

begin

    clk <= not clk after CLK_PERIOD / 2;

    dut : entity work.tile_scheduler
        generic map (
            N         => 4,
            TILE_SIZE => 2
        )
        port map (
            clk      => clk,
            rst      => rst,
            start    => start,
            advance  => advance,
            busy     => busy,
            valid    => valid,
            done     => done,
            first_k  => first_k,
            tile_row => tile_row,
            tile_col => tile_col,
            tile_k   => tile_k
        );

    stim_proc : process
    begin
        rst <= '1';
        wait for 3 * CLK_PERIOD;
        rst <= '0';
        wait until rising_edge(clk);

        start <= '1';
        wait until rising_edge(clk);
        start <= '0';
        wait for 1 ns;

        assert busy = '1' and valid = '1' and first_k = '1'
            report "tile_scheduler nao iniciou corretamente."
            severity failure;

        for idx in 0 to 7 loop
            advance <= '1';
            wait until rising_edge(clk);
            advance <= '0';
            wait until rising_edge(clk);
        end loop;

        wait for 1 ns;

        assert done = '1'
            report "tile_scheduler nao finalizou apos todos os tiles."
            severity failure;

        report "SIM_RESULT: PASS" severity note;
        finish;
    end process;

end architecture sim;
