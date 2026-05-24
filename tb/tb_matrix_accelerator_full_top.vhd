library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_matrix_accelerator_full_top is
end entity tb_matrix_accelerator_full_top;

architecture sim of tb_matrix_accelerator_full_top is

    constant CLK_PERIOD       : time := 10 ns;
    constant CLKS_PER_BIT     : positive := 8;
    constant TILE_SIZE        : positive := 2;
    constant NUM_MACS         : positive := 2;
    constant DATA_WIDTH       : positive := 8;
    constant ACC_WIDTH        : positive := 32;
    constant SDRAM_DATA_WIDTH : positive := 32;
    constant SDRAM_ADDR_WIDTH : positive := 10;
    constant SDRAM_DEPTH      : positive := 1024;

    constant N4 : positive := 4;
    constant N8 : positive := 8;

    constant CMD_LOAD_A      : std_logic_vector(7 downto 0) := x"41";
    constant CMD_LOAD_B      : std_logic_vector(7 downto 0) := x"42";
    constant CMD_START       : std_logic_vector(7 downto 0) := x"53";
    constant CMD_READ_C      : std_logic_vector(7 downto 0) := x"52";
    constant CMD_READ_STATUS : std_logic_vector(7 downto 0) := x"3F";
    constant RESP_ACK        : std_logic_vector(7 downto 0) := x"06";

    signal clk : std_logic := '0';
    signal rst : std_logic := '0';

    signal uart_rx4_i : std_logic := '1';
    signal uart_tx4_o : std_logic;
    signal busy4_led  : std_logic;
    signal done4_led  : std_logic;

    signal uart_rx8_i : std_logic := '1';
    signal uart_tx8_o : std_logic;
    signal busy8_led  : std_logic;
    signal done8_led  : std_logic;

    function a_value(
        constant row_idx : natural;
        constant col_idx : natural
    ) return integer is
    begin
        return (row_idx + (2 * col_idx) + 1) mod 8;
    end function;

    function b_value(
        constant row_idx : natural;
        constant col_idx : natural
    ) return integer is
    begin
        return ((3 * row_idx) + col_idx + 2) mod 8;
    end function;

    function c_expected(
        constant n_value : positive;
        constant row_idx : natural;
        constant col_idx : natural
    ) return integer is
        variable acc : integer := 0;
    begin
        for k_idx in 0 to n_value-1 loop
            acc := acc + a_value(row_idx, k_idx) * b_value(k_idx, col_idx);
        end loop;

        return acc;
    end function;

    procedure wait_cycles(constant count : natural) is
    begin
        for cycle_idx in 1 to count loop
            wait until rising_edge(clk);
        end loop;
    end procedure;

    procedure uart_send_byte(
        signal rx_line : out std_logic;
        constant value : std_logic_vector(7 downto 0)
    ) is
    begin
        rx_line <= '0';
        wait_cycles(CLKS_PER_BIT);

        for bit_idx in 0 to 7 loop
            rx_line <= value(bit_idx);
            wait_cycles(CLKS_PER_BIT);
        end loop;

        rx_line <= '1';
        wait_cycles(CLKS_PER_BIT + 2);
    end procedure;

    procedure uart_send_word32(
        signal rx_line : out std_logic;
        constant value : std_logic_vector(31 downto 0)
    ) is
    begin
        uart_send_byte(rx_line, value(31 downto 24));
        uart_send_byte(rx_line, value(23 downto 16));
        uart_send_byte(rx_line, value(15 downto 8));
        uart_send_byte(rx_line, value(7 downto 0));
    end procedure;

    procedure uart_recv_byte(
        signal tx_line : in std_logic;
        variable value : out std_logic_vector(7 downto 0)
    ) is
    begin
        if tx_line /= '0' then
            wait until tx_line = '0';
        end if;

        wait_cycles(CLKS_PER_BIT + (CLKS_PER_BIT / 2));

        for bit_idx in 0 to 7 loop
            value(bit_idx) := tx_line;
            wait_cycles(CLKS_PER_BIT);
        end loop;

        wait_cycles(CLKS_PER_BIT);
    end procedure;

    procedure uart_recv_word32(
        signal tx_line : in std_logic;
        variable value : out std_logic_vector(31 downto 0)
    ) is
        variable byte_value : std_logic_vector(7 downto 0);
    begin
        uart_recv_byte(tx_line, byte_value);
        value(31 downto 24) := byte_value;
        uart_recv_byte(tx_line, byte_value);
        value(23 downto 16) := byte_value;
        uart_recv_byte(tx_line, byte_value);
        value(15 downto 8) := byte_value;
        uart_recv_byte(tx_line, byte_value);
        value(7 downto 0) := byte_value;
    end procedure;

    procedure expect_ack(
        signal tx_line : in std_logic;
        constant label_text : string
    ) is
        variable byte_value : std_logic_vector(7 downto 0);
    begin
        uart_recv_byte(tx_line, byte_value);

        assert byte_value = RESP_ACK
            report label_text & ": ACK UART incorreto."
            severity failure;
    end procedure;

    procedure send_load(
        signal rx_line : out std_logic;
        signal tx_line : in std_logic;
        constant opcode : std_logic_vector(7 downto 0);
        constant addr   : natural;
        constant value  : integer;
        constant label_text : string
    ) is
    begin
        uart_send_byte(rx_line, opcode);
        uart_send_word32(rx_line, std_logic_vector(to_unsigned(addr, 32)));
        uart_send_word32(rx_line, std_logic_vector(to_signed(value, 32)));
        expect_ack(tx_line, label_text);
    end procedure;

    procedure read_status(
        signal rx_line : out std_logic;
        signal tx_line : in std_logic;
        variable status_word : out std_logic_vector(31 downto 0)
    ) is
    begin
        uart_send_byte(rx_line, CMD_READ_STATUS);
        uart_recv_word32(tx_line, status_word);
    end procedure;

    procedure read_c(
        signal rx_line : out std_logic;
        signal tx_line : in std_logic;
        constant addr  : natural;
        variable value : out integer
    ) is
        variable word_value : std_logic_vector(31 downto 0);
    begin
        uart_send_byte(rx_line, CMD_READ_C);
        uart_send_word32(rx_line, std_logic_vector(to_unsigned(addr, 32)));
        uart_recv_word32(tx_line, word_value);
        value := to_integer(signed(word_value));
    end procedure;

    procedure run_uart_matrix_test(
        signal rx_line  : out std_logic;
        signal tx_line  : in std_logic;
        signal done_led : in std_logic;
        constant n_value : positive;
        constant label_text : string
    ) is
        variable addr        : natural;
        variable status_word : std_logic_vector(31 downto 0);
        variable got_value   : integer;
        variable done_seen   : boolean := false;
    begin
        for row_idx in 0 to n_value-1 loop
            for col_idx in 0 to n_value-1 loop
                addr := row_idx * n_value + col_idx;

                send_load(rx_line, tx_line, CMD_LOAD_A, addr, a_value(row_idx, col_idx), label_text & " LOAD_A");
                send_load(rx_line, tx_line, CMD_LOAD_B, addr, b_value(row_idx, col_idx), label_text & " LOAD_B");
            end loop;
        end loop;

        uart_send_byte(rx_line, CMD_START);
        expect_ack(tx_line, label_text & " START");

        for poll_idx in 0 to 400 loop
            read_status(rx_line, tx_line, status_word);

            if status_word(1) = '1' or done_led = '1' then
                done_seen := true;
                exit;
            end if;
        end loop;

        assert done_seen
            report label_text & ": acelerador nao sinalizou done/status."
            severity failure;

        for row_idx in 0 to n_value-1 loop
            for col_idx in 0 to n_value-1 loop
                addr := row_idx * n_value + col_idx;
                read_c(rx_line, tx_line, addr, got_value);

                assert got_value = c_expected(n_value, row_idx, col_idx)
                    report label_text & ": resultado C incorreto."
                    severity failure;
            end loop;
        end loop;
    end procedure;

begin

    clk <= not clk after CLK_PERIOD / 2;

    dut_n4 : entity work.matrix_accelerator_full_top
        generic map (
            N                => N4,
            TILE_SIZE        => TILE_SIZE,
            NUM_MACS         => NUM_MACS,
            DATA_WIDTH       => DATA_WIDTH,
            ACC_WIDTH        => ACC_WIDTH,
            SDRAM_DATA_WIDTH => SDRAM_DATA_WIDTH,
            SDRAM_ADDR_WIDTH => SDRAM_ADDR_WIDTH,
            SDRAM_DEPTH      => SDRAM_DEPTH,
            READ_LATENCY     => 1,
            WRITE_LATENCY    => 1,
            CLKS_PER_BIT     => CLKS_PER_BIT
        )
        port map (
            clk          => clk,
            rst          => rst,
            uart_rx_i    => uart_rx4_i,
            uart_tx_o    => uart_tx4_o,
            start_button => '0',
            busy_led     => busy4_led,
            done_led     => done4_led
        );

    dut_n8 : entity work.matrix_accelerator_full_top
        generic map (
            N                => N8,
            TILE_SIZE        => TILE_SIZE,
            NUM_MACS         => NUM_MACS,
            DATA_WIDTH       => DATA_WIDTH,
            ACC_WIDTH        => ACC_WIDTH,
            SDRAM_DATA_WIDTH => SDRAM_DATA_WIDTH,
            SDRAM_ADDR_WIDTH => SDRAM_ADDR_WIDTH,
            SDRAM_DEPTH      => SDRAM_DEPTH,
            READ_LATENCY     => 1,
            WRITE_LATENCY    => 1,
            CLKS_PER_BIT     => CLKS_PER_BIT
        )
        port map (
            clk          => clk,
            rst          => rst,
            uart_rx_i    => uart_rx8_i,
            uart_tx_o    => uart_tx8_o,
            start_button => '0',
            busy_led     => busy8_led,
            done_led     => done8_led
        );

    stim_proc : process
    begin
        rst <= '1';
        wait_cycles(6);
        rst <= '0';
        wait_cycles(6);

        assert uart_tx4_o = '1' and uart_tx8_o = '1'
            report "UART TX deveria ficar em repouso alto apos reset."
            severity failure;

        run_uart_matrix_test(uart_rx4_i, uart_tx4_o, done4_led, N4, "N=4");
        run_uart_matrix_test(uart_rx8_i, uart_tx8_o, done8_led, N8, "N=8");

        report "SIM_RESULT: PASS" severity note;
        finish;
    end process;

end architecture sim;
