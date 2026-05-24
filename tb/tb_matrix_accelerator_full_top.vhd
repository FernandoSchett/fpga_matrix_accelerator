library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_matrix_accelerator_full_top is
end entity tb_matrix_accelerator_full_top;

architecture sim of tb_matrix_accelerator_full_top is

    constant CLK_PERIOD : time := 10 ns;

    signal clk : std_logic := '0';
    signal rst : std_logic := '0';

    signal uart_rx_i : std_logic := '1';
    signal uart_tx_o : std_logic;
    signal start_button : std_logic := '0';
    signal busy_led : std_logic;
    signal done_led : std_logic;

begin

    clk <= not clk after CLK_PERIOD / 2;

    dut : entity work.matrix_accelerator_full_top
        generic map (
            N                => 4,
            TILE_SIZE        => 2,
            NUM_MACS         => 2,
            DATA_WIDTH       => 8,
            ACC_WIDTH        => 32,
            SDRAM_DATA_WIDTH => 32,
            SDRAM_ADDR_WIDTH => 8,
            CLKS_PER_BIT     => 8
        )
        port map (
            clk          => clk,
            rst          => rst,
            uart_rx_i    => uart_rx_i,
            uart_tx_o    => uart_tx_o,
            start_button => start_button,
            busy_led     => busy_led,
            done_led     => done_led
        );

    stim_proc : process
    begin
        rst <= '1';
        wait for 3 * CLK_PERIOD;
        rst <= '0';
        wait until rising_edge(clk);

        assert uart_tx_o = '1'
            report "UART TX deveria ficar em repouso alto."
            severity failure;

        start_button <= '1';
        wait until rising_edge(clk);
        start_button <= '0';

        for cycle_idx in 0 to 5000 loop
            wait until rising_edge(clk);
            exit when done_led = '1';
        end loop;

        assert done_led = '1'
            report "matrix_accelerator_full_top nao finalizou com matrizes zeradas."
            severity failure;

        report "SIM_RESULT: PASS" severity note;
        finish;
    end process;

end architecture sim;
