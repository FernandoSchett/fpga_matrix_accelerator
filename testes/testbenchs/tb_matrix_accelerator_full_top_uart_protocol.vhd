library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_matrix_accelerator_full_top_uart_protocol is
end entity;

architecture sim of tb_matrix_accelerator_full_top_uart_protocol is

    constant CLK_PERIOD   : time := 10 ns;
    constant CLKS_PER_BIT : positive := 8;

    constant N_SIM         : positive := 4;
    constant TILE_SIZE_SIM : positive := 2;
    constant NUM_MACS_SIM  : positive := 2;

    constant CMD_LOAD_A        : std_logic_vector(7 downto 0) := x"41"; -- 'A'
    constant CMD_LOAD_B        : std_logic_vector(7 downto 0) := x"42"; -- 'B'
    constant CMD_START         : std_logic_vector(7 downto 0) := x"53"; -- 'S'
    constant CMD_READ_C        : std_logic_vector(7 downto 0) := x"52"; -- 'R'
    constant CMD_READ_STATUS   : std_logic_vector(7 downto 0) := x"3F"; -- '?'
    constant CMD_READ_COUNTERS : std_logic_vector(7 downto 0) := x"50"; -- 'P'

    constant RESP_ACK : std_logic_vector(7 downto 0) := x"06";
    constant RESP_NAK : std_logic_vector(7 downto 0) := x"15";

    signal clk          : std_logic := '0';
    signal rst          : std_logic := '0';
    signal uart_rx_i    : std_logic := '1';
    signal uart_tx_o    : std_logic;
    signal start_button : std_logic := '0';

    signal LEDR : std_logic_vector(9 downto 0);
    signal HEX0 : std_logic_vector(6 downto 0);
    signal HEX1 : std_logic_vector(6 downto 0);
    signal HEX2 : std_logic_vector(6 downto 0);
    signal HEX3 : std_logic_vector(6 downto 0);
    signal HEX4 : std_logic_vector(6 downto 0);
    signal HEX5 : std_logic_vector(6 downto 0);

    type int_matrix_t is array (0 to N_SIM-1, 0 to N_SIM-1) of integer;

    constant A_MAT : int_matrix_t := (
        (1, 2, 0, 1),
        (0, 1, 3, 0),
        (4, 0, 1, 2),
        (1, 0, 0, 1)
    );

    constant B_MAT : int_matrix_t := (
        (1, 0, 2, 1),
        (0, 1, 1, 0),
        (3, 2, 0, 1),
        (1, 1, 1, 1)
    );

    constant C_EXPECTED : int_matrix_t := (
        (2, 3, 5, 2),
        (9, 7, 1, 3),
        (9, 4, 10, 7),
        (2, 1, 3, 2)
    );

    procedure wait_cycles(constant count : natural) is
    begin
        for idx in 1 to count loop
            wait until rising_edge(clk);
        end loop;
    end procedure;

    procedure uart_send_byte(
        signal rx_line : out std_logic;
        constant value : std_logic_vector(7 downto 0)
    ) is
    begin
        wait until rising_edge(clk);

        -- start bit
        rx_line <= '0';
        wait_cycles(CLKS_PER_BIT);

        -- data bits, LSB first
        for bit_idx in 0 to 7 loop
            rx_line <= value(bit_idx);
            wait_cycles(CLKS_PER_BIT);
        end loop;

        -- stop bit
        rx_line <= '1';
        wait_cycles(CLKS_PER_BIT);
    end procedure;

    procedure uart_read_byte(
        signal tx_line : in std_logic;
        variable value : out std_logic_vector(7 downto 0)
    ) is
    begin
        wait until tx_line = '0';

        -- sample near center of first data bit
        wait_cycles(CLKS_PER_BIT + (CLKS_PER_BIT / 2));

        for bit_idx in 0 to 7 loop
            value(bit_idx) := tx_line;

            if bit_idx < 7 then
                wait_cycles(CLKS_PER_BIT);
            end if;
        end loop;

        wait_cycles(CLKS_PER_BIT);

        assert tx_line = '1'
            report "UART TX stop bit nao esta em nivel alto."
            severity failure;
    end procedure;

    procedure uart_send_word_be(
        signal rx_line : out std_logic;
        constant value : std_logic_vector(31 downto 0)
    ) is
    begin
        uart_send_byte(rx_line, value(31 downto 24));
        uart_send_byte(rx_line, value(23 downto 16));
        uart_send_byte(rx_line, value(15 downto 8));
        uart_send_byte(rx_line, value(7 downto 0));
    end procedure;

    procedure uart_read_word_be(
        signal tx_line : in std_logic;
        variable value : out std_logic_vector(31 downto 0)
    ) is
        variable b0 : std_logic_vector(7 downto 0);
        variable b1 : std_logic_vector(7 downto 0);
        variable b2 : std_logic_vector(7 downto 0);
        variable b3 : std_logic_vector(7 downto 0);
    begin
        uart_read_byte(tx_line, b0);
        uart_read_byte(tx_line, b1);
        uart_read_byte(tx_line, b2);
        uart_read_byte(tx_line, b3);

        value := b0 & b1 & b2 & b3;
    end procedure;

    procedure uart_expect_byte(
        signal tx_line : in std_logic;
        constant expected : std_logic_vector(7 downto 0);
        constant label_msg : string
    ) is
        variable got : std_logic_vector(7 downto 0);
    begin
        uart_read_byte(tx_line, got);

        assert got = expected
            report label_msg & ": byte inesperado. Esperado=" &
                   integer'image(to_integer(unsigned(expected))) &
                   " recebido=" &
                   integer'image(to_integer(unsigned(got)))
            severity failure;
    end procedure;

    procedure uart_write_matrix_word(
        signal rx_line : out std_logic;
        signal tx_line : in std_logic;
        constant cmd   : std_logic_vector(7 downto 0);
        constant addr  : natural;
        constant value : integer
    ) is
    begin
        uart_send_byte(rx_line, cmd);
        uart_send_word_be(rx_line, std_logic_vector(to_unsigned(addr, 32)));
        uart_send_word_be(rx_line, std_logic_vector(to_signed(value, 32)));

        uart_expect_byte(tx_line, RESP_ACK, "LOAD deveria retornar ACK");
    end procedure;

begin

    clk <= not clk after CLK_PERIOD / 2;

    dut : entity work.matrix_accelerator_full_top
        generic map (
            N                   => N_SIM,
            TILE_SIZE           => TILE_SIZE_SIM,
            NUM_MACS            => NUM_MACS_SIM,
            DATA_WIDTH          => 8,
            ACC_WIDTH           => 32,
            MEM_TYPE            => "internal_fpga_ram",
            DATAFLOW            => "output_stationary",
            BUFFERING_MODE      => "single",
            MEMORY_BURST_LEN    => 1,
            MAC_PIPELINE_STAGES => 0,
            MEMORY_BANKS_A      => 1,
            MEMORY_BANKS_B      => 1,
            CLKS_PER_BIT        => CLKS_PER_BIT,
            CLK_FREQ_HZ         => 1000,
            UART_FIFO_DEPTH     => 64,
            ENABLE_SIGNALTAP    => false
        )
        port map (
            clk          => clk,
            rst          => rst,
            uart_rx_i    => uart_rx_i,
            uart_tx_o    => uart_tx_o,
            start_button => start_button,
            LEDR         => LEDR,
            HEX0         => HEX0,
            HEX1         => HEX1,
            HEX2         => HEX2,
            HEX3         => HEX3,
            HEX4         => HEX4,
            HEX5         => HEX5
        );

    stim_proc : process
        variable status_word  : std_logic_vector(31 downto 0);
        variable result_word  : std_logic_vector(31 downto 0);
        variable counter_word : std_logic_vector(31 downto 0);
        variable got_int      : integer;
        variable addr         : natural;
        variable done_seen    : boolean := false;
    begin
        report "SIM: reset inicial" severity note;

        rst <= '1';
        uart_rx_i <= '1';
        start_button <= '0';
        wait_cycles(10);

        rst <= '0';
        wait_cycles(10);

        assert uart_tx_o = '1'
            report "uart_tx_o deveria estar em repouso alto depois do reset."
            severity failure;

        report "SIM: testando comando invalido -> NAK" severity note;

        uart_send_byte(uart_rx_i, x"00");
        uart_expect_byte(uart_tx_o, RESP_NAK, "Comando invalido deveria retornar NAK");

        report "SIM: carregando matriz A via UART" severity note;

        for row_idx in 0 to N_SIM-1 loop
            for col_idx in 0 to N_SIM-1 loop
                addr := row_idx * N_SIM + col_idx;
                uart_write_matrix_word(
                    uart_rx_i,
                    uart_tx_o,
                    CMD_LOAD_A,
                    addr,
                    A_MAT(row_idx, col_idx)
                );
            end loop;
        end loop;

        report "SIM: carregando matriz B via UART" severity note;

        for row_idx in 0 to N_SIM-1 loop
            for col_idx in 0 to N_SIM-1 loop
                addr := row_idx * N_SIM + col_idx;
                uart_write_matrix_word(
                    uart_rx_i,
                    uart_tx_o,
                    CMD_LOAD_B,
                    addr,
                    B_MAT(row_idx, col_idx)
                );
            end loop;
        end loop;

        report "SIM: enviando START via UART" severity note;

        uart_send_byte(uart_rx_i, CMD_START);
        uart_expect_byte(uart_tx_o, RESP_ACK, "START deveria retornar ACK");

        report "SIM: aguardando done por READ_STATUS" severity note;

        for poll_idx in 0 to 200 loop
            uart_send_byte(uart_rx_i, CMD_READ_STATUS);
            uart_read_word_be(uart_tx_o, status_word);

            if status_word(1) = '1' then
                done_seen := true;
                exit;
            end if;

            wait_cycles(20);
        end loop;

        assert done_seen
            report "Acelerador nao sinalizou done via READ_STATUS."
            severity failure;

        assert LEDR(8) = '1'
            report "LEDR(8) deveria estar latched apos done."
            severity failure;

        report "SIM: lendo matriz C via UART e comparando resultado" severity note;

        for row_idx in 0 to N_SIM-1 loop
            for col_idx in 0 to N_SIM-1 loop
                addr := row_idx * N_SIM + col_idx;

                uart_send_byte(uart_rx_i, CMD_READ_C);
                uart_send_word_be(uart_rx_i, std_logic_vector(to_unsigned(addr, 32)));
                uart_read_word_be(uart_tx_o, result_word);

                got_int := to_integer(signed(result_word));

                assert got_int = C_EXPECTED(row_idx, col_idx)
                    report "Resultado C incorreto em addr=" &
                           integer'image(addr) &
                           ". Esperado=" &
                           integer'image(C_EXPECTED(row_idx, col_idx)) &
                           " recebido=" &
                           integer'image(got_int)
                    severity failure;
            end loop;
        end loop;

        report "SIM: lendo contadores de performance" severity note;

        uart_send_byte(uart_rx_i, CMD_READ_COUNTERS);

        for counter_idx in 0 to 5 loop
            uart_read_word_be(uart_tx_o, counter_word);

            if counter_idx = 0 then
                assert unsigned(counter_word) > 0
                    report "perf_total_cycles deveria ser maior que zero."
                    severity failure;
            elsif counter_idx = 2 then
                assert unsigned(counter_word) > 0
                    report "perf_compute_cycles deveria ser maior que zero."
                    severity failure;
            elsif counter_idx = 4 then
                assert unsigned(counter_word) > 0
                    report "perf_num_tiles_processed deveria ser maior que zero."
                    severity failure;
            end if;
        end loop;

        report "SIM_RESULT: PASS - protocolo UART + LOAD + START + READ_C funcionando" severity note;
        finish;
    end process;

end architecture sim;