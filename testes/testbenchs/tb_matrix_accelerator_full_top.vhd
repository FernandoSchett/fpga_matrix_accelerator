library ieee;
use ieee.std_logic_1164.all;
use std.env.all;

entity tb_matrix_accelerator_full_top is
end entity tb_matrix_accelerator_full_top;

architecture sim of tb_matrix_accelerator_full_top is

    constant CLK_PERIOD  : time := 10 ns;
    constant CLKS_PER_BIT : positive := 8;

    signal clk : std_logic := '0';
    signal rst : std_logic := '0';
    signal uart_rx_i : std_logic := '1';
    signal uart_tx_o : std_logic;
    signal start_button : std_logic := '0';
    signal busy_led : std_logic;
    signal done_led : std_logic;
    signal ledr : std_logic_vector(9 downto 0);

    procedure wait_cycles(constant count : natural) is
    begin
        for idx in 1 to count loop
            wait until rising_edge(clk);
        end loop;
    end procedure;

begin

    clk <= not clk after CLK_PERIOD / 2;

    dut : entity work.matrix_accelerator_full_top
        generic map (
            N            => 4,
            TILE_SIZE    => 2,
            NUM_MACS     => 2,
            DATA_WIDTH   => 8,
            ACC_WIDTH    => 32,
            CLKS_PER_BIT => CLKS_PER_BIT,
            CLK_FREQ_HZ  => 1000
        )
        port map (
            clk          => clk,
            rst          => rst,
            uart_rx_i    => uart_rx_i,
            uart_tx_o    => uart_tx_o,
            start_button => start_button,
            busy_led     => busy_led,
            done_led     => done_led,
            LEDR         => ledr
        );

    stim_proc : process
    begin
        rst <= '1';
        wait_cycles(6);
        rst <= '0';
        wait_cycles(6);

        assert uart_tx_o = '1'
            report "UART TX deveria ficar em repouso alto apos reset."
            severity failure;

        start_button <= '1';
        wait until rising_edge(clk);
        start_button <= '0';

        wait_cycles(2);
        assert busy_led = '1'
            report "busy_led deveria acender apos start_button."
            severity failure;

        for cycle_idx in 0 to 2000 loop
            wait until rising_edge(clk);
            exit when done_led = '1';
        end loop;

        assert done_led = '1'
            report "matrix_accelerator_full_top nao finalizou."
            severity failure;

        assert ledr(8) = '1'
            report "LEDR8 done_latched nao acendeu."
            severity failure;

        report "SIM_RESULT: PASS" severity note;
        finish;
    end process;

end architecture sim;
