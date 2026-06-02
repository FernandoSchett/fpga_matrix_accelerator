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
    signal ledr : std_logic_vector(9 downto 0);
    signal HEX0 : std_logic_vector(6 downto 0);
    signal HEX1 : std_logic_vector(6 downto 0);
    signal HEX2 : std_logic_vector(6 downto 0);
    signal HEX3 : std_logic_vector(6 downto 0);
    signal HEX4 : std_logic_vector(6 downto 0);
    signal HEX5 : std_logic_vector(6 downto 0);
    signal DRAM_ADDR  : std_logic_vector(12 downto 0);
    signal DRAM_BA    : std_logic_vector(1 downto 0);
    signal DRAM_CAS_N : std_logic;
    signal DRAM_CKE   : std_logic;
    signal DRAM_CLK   : std_logic;
    signal DRAM_CS_N  : std_logic;
    signal DRAM_DQ    : std_logic_vector(15 downto 0);
    signal DRAM_LDQM  : std_logic;
    signal DRAM_RAS_N : std_logic;
    signal DRAM_UDQM  : std_logic;
    signal DRAM_WE_N  : std_logic;

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
            SDRAM_SIMULATION_MODEL => true,
            CLKS_PER_BIT => CLKS_PER_BIT,
            CLK_FREQ_HZ  => 1000,
            UART_FIFO_DEPTH => 16,
            ENABLE_SIGNALTAP => false
        )
        port map (
            clk          => clk,
            rst          => rst,
            uart_rx_i    => uart_rx_i,
            uart_tx_o    => uart_tx_o,
            start_button => start_button,
            LEDR         => ledr,
            HEX0         => HEX0,
            HEX1         => HEX1,
            HEX2         => HEX2,
            HEX3         => HEX3,
            HEX4         => HEX4,
            HEX5         => HEX5,
            DRAM_ADDR    => DRAM_ADDR,
            DRAM_BA      => DRAM_BA,
            DRAM_CAS_N   => DRAM_CAS_N,
            DRAM_CKE     => DRAM_CKE,
            DRAM_CLK     => DRAM_CLK,
            DRAM_CS_N    => DRAM_CS_N,
            DRAM_DQ      => DRAM_DQ,
            DRAM_LDQM    => DRAM_LDQM,
            DRAM_RAS_N   => DRAM_RAS_N,
            DRAM_UDQM    => DRAM_UDQM,
            DRAM_WE_N    => DRAM_WE_N
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
        wait_cycles(3);
        start_button <= '0';
        wait_cycles(3);

        assert ledr(5) = '0'
            report "start_button deve ficar desabilitado; START valido vem da UART."
            severity failure;

        report "SIM_RESULT: PASS" severity note;
        finish;
    end process;

end architecture sim;
