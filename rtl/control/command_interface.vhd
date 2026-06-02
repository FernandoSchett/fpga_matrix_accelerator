library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.matrix_accel_config_pkg.all;

entity command_interface is
    generic (
        ADDR_WIDTH        : positive := DEFAULT_ADDR_WIDTH;
        DATA_WIDTH        : positive := DEFAULT_HOST_DATA_WIDTH;
        COUNTER_WIDTH     : positive := 64
    );
    port (
        clk : in std_logic;
        rst : in std_logic;

        rx_valid : in std_logic;
        rx_byte  : in std_logic_vector(7 downto 0);
        rx_ready : out std_logic;

        tx_busy  : in std_logic;
        tx_start : out std_logic;
        tx_byte  : out std_logic_vector(7 downto 0);

        accelerator_busy : in std_logic;
        accelerator_done : in std_logic;

        host_cmd_valid  : out std_logic;
        host_cmd_write  : out std_logic;
        host_cmd_ready  : in std_logic;
        host_matrix_sel : out std_logic_vector(1 downto 0);
        host_addr       : out unsigned(ADDR_WIDTH-1 downto 0);
        host_data_in    : out std_logic_vector(DATA_WIDTH-1 downto 0);
        host_data_out   : in std_logic_vector(DATA_WIDTH-1 downto 0);
        host_rd_valid   : in std_logic;

        start : out std_logic;
        clear : out std_logic;

        perf_total_cycles        : in unsigned(COUNTER_WIDTH-1 downto 0);
        perf_load_cycles         : in unsigned(COUNTER_WIDTH-1 downto 0);
        perf_compute_cycles      : in unsigned(COUNTER_WIDTH-1 downto 0);
        perf_store_cycles        : in unsigned(COUNTER_WIDTH-1 downto 0);
        perf_num_tiles_processed : in unsigned(COUNTER_WIDTH-1 downto 0);
        perf_num_mac_ops_issued  : in unsigned(COUNTER_WIDTH-1 downto 0)
    );
end entity command_interface;

architecture rtl of command_interface is

    constant CMD_LOAD_A        : std_logic_vector(7 downto 0) := x"41"; -- 'A'
    constant CMD_LOAD_B        : std_logic_vector(7 downto 0) := x"42"; -- 'B'
    constant CMD_CLEAR         : std_logic_vector(7 downto 0) := x"43"; -- 'C'
    constant CMD_START         : std_logic_vector(7 downto 0) := x"53"; -- 'S'
    constant CMD_READ_C        : std_logic_vector(7 downto 0) := x"52"; -- 'R'
    constant CMD_READ_STATUS   : std_logic_vector(7 downto 0) := x"3F"; -- '?'
    constant CMD_READ_COUNTERS : std_logic_vector(7 downto 0) := x"50"; -- 'P'

    constant RESP_ACK : std_logic_vector(7 downto 0) := x"06";
    constant RESP_NAK : std_logic_vector(7 downto 0) := x"15";

    type state_t is (
        IDLE,
        RECV_ADDR,
        RECV_DATA,
        ISSUE_LOAD,
        ISSUE_START,
        ISSUE_CLEAR,
        ISSUE_READ_C,
        WAIT_READ_C,
        PREP_STATUS,
        PREP_COUNTER,
        SEND_ACK,
        SEND_NAK,
        SEND_WORD
    );

    signal state : state_t := IDLE;

    signal opcode_reg : std_logic_vector(7 downto 0) := (others => '0');
    signal addr_shift : std_logic_vector(31 downto 0) := (others => '0');
    signal data_shift : std_logic_vector(31 downto 0) := (others => '0');
    signal byte_count : integer range 0 to 3 := 0;

    signal tx_start_reg : std_logic := '0';
    signal tx_byte_reg  : std_logic_vector(7 downto 0) := (others => '0');
    signal tx_word_reg  : std_logic_vector(31 downto 0) := (others => '0');
    signal tx_index     : integer range 0 to 3 := 0;

    signal counter_index   : integer range 0 to 5 := 0;

    signal host_matrix_sel_reg : std_logic_vector(1 downto 0) := MATRIX_ID_A;
    signal host_addr_reg       : unsigned(ADDR_WIDTH-1 downto 0) := (others => '0');
    signal host_data_in_reg    : std_logic_vector(DATA_WIDTH-1 downto 0) := (others => '0');
    signal host_cmd_valid_reg  : std_logic := '0';
    signal host_cmd_write_reg  : std_logic := '0';
    signal start_reg           : std_logic := '0';
    signal clear_reg           : std_logic := '0';

    function low32(constant value : unsigned) return std_logic_vector is
        variable result : std_logic_vector(31 downto 0) := (others => '0');
    begin
        for idx in 0 to 31 loop
            if idx < value'length then
                result(idx) := value(idx);
            end if;
        end loop;

        return result;
    end function;

begin

    tx_start <= tx_start_reg;
    tx_byte  <= tx_byte_reg;

    host_cmd_valid  <= host_cmd_valid_reg;
    host_cmd_write  <= host_cmd_write_reg;
    host_matrix_sel <= host_matrix_sel_reg;
    host_addr       <= host_addr_reg;
    host_data_in    <= host_data_in_reg;
    start           <= start_reg;
    clear           <= clear_reg;

    rx_ready <= '1' when state = IDLE or state = RECV_ADDR or state = RECV_DATA else '0';

    process(clk, rst)
        variable next_addr  : std_logic_vector(31 downto 0);
        variable next_data  : std_logic_vector(31 downto 0);
        variable status_word : std_logic_vector(31 downto 0);
    begin
        if rst = '1' then
            state               <= IDLE;
            opcode_reg          <= (others => '0');
            addr_shift          <= (others => '0');
            data_shift          <= (others => '0');
            byte_count          <= 0;
            tx_start_reg        <= '0';
            tx_byte_reg         <= (others => '0');
            tx_word_reg         <= (others => '0');
            tx_index            <= 0;
            counter_index       <= 0;
            host_matrix_sel_reg <= MATRIX_ID_A;
            host_addr_reg       <= (others => '0');
            host_data_in_reg    <= (others => '0');
            host_cmd_valid_reg  <= '0';
            host_cmd_write_reg  <= '0';
            start_reg           <= '0';
            clear_reg           <= '0';

        elsif rising_edge(clk) then
            tx_start_reg   <= '0';
            start_reg      <= '0';
            clear_reg      <= '0';

            case state is
                when IDLE =>
                    byte_count <= 0;
                    tx_index   <= 0;
                    host_cmd_valid_reg <= '0';
                    host_cmd_write_reg <= '0';

                    if rx_valid = '1' then
                        opcode_reg <= rx_byte;

                        if rx_byte = CMD_LOAD_A or rx_byte = CMD_LOAD_B or rx_byte = CMD_READ_C then
                            addr_shift <= (others => '0');
                            state      <= RECV_ADDR;

                        elsif rx_byte = CMD_START then
                            state <= ISSUE_START;

                        elsif rx_byte = CMD_CLEAR then
                            state <= ISSUE_CLEAR;

                        elsif rx_byte = CMD_READ_STATUS then
                            state <= PREP_STATUS;

                        elsif rx_byte = CMD_READ_COUNTERS then
                            counter_index <= 0;
                            state         <= PREP_COUNTER;

                        else
                            state <= SEND_NAK;
                        end if;
                    end if;

                when RECV_ADDR =>
                    if rx_valid = '1' then
                        next_addr := addr_shift(23 downto 0) & rx_byte;
                        addr_shift <= next_addr;

                        if byte_count = 3 then
                            byte_count <= 0;

                            if opcode_reg = CMD_READ_C then
                                host_addr_reg <= resize(unsigned(next_addr), ADDR_WIDTH);
                                host_cmd_valid_reg <= '1';
                                host_cmd_write_reg <= '0';
                                state         <= ISSUE_READ_C;
                            else
                                data_shift <= (others => '0');
                                state      <= RECV_DATA;
                            end if;
                        else
                            byte_count <= byte_count + 1;
                        end if;
                    end if;

                when RECV_DATA =>
                    if rx_valid = '1' then
                        next_data := data_shift(23 downto 0) & rx_byte;
                        data_shift <= next_data;

                        if byte_count = 3 then
                            byte_count <= 0;
                            host_addr_reg    <= resize(unsigned(addr_shift), ADDR_WIDTH);
                            host_data_in_reg <= std_logic_vector(resize(unsigned(next_data), DATA_WIDTH));

                            if opcode_reg = CMD_LOAD_A then
                                host_matrix_sel_reg <= MATRIX_ID_A;
                            else
                                host_matrix_sel_reg <= MATRIX_ID_B;
                            end if;

                            host_cmd_valid_reg <= '1';
                            host_cmd_write_reg <= '1';
                            state <= ISSUE_LOAD;
                        else
                            byte_count <= byte_count + 1;
                        end if;
                    end if;

                when ISSUE_LOAD =>
                    host_cmd_valid_reg <= '1';
                    host_cmd_write_reg <= '1';
                    if host_cmd_ready = '1' then
                        host_cmd_valid_reg <= '0';
                        host_cmd_write_reg <= '0';
                        state <= SEND_ACK;
                    end if;

                when ISSUE_START =>
                    if accelerator_busy = '1' then
                        state <= SEND_NAK;
                    elsif host_cmd_ready = '1' then
                        start_reg <= '1';
                        state     <= SEND_ACK;
                    end if;

                when ISSUE_CLEAR =>
                    if accelerator_busy = '0' then
                        clear_reg <= '1';
                        state     <= SEND_ACK;
                    else
                        state <= SEND_NAK;
                    end if;

                when ISSUE_READ_C =>
                    host_cmd_valid_reg <= '1';
                    host_cmd_write_reg <= '0';
                    if host_cmd_ready = '1' then
                        host_cmd_valid_reg <= '0';
                        state <= WAIT_READ_C;
                    end if;

                when WAIT_READ_C =>
                    if host_rd_valid = '1' then
                        tx_word_reg <= std_logic_vector(resize(unsigned(host_data_out), 32));
                        tx_index    <= 0;
                        state       <= SEND_WORD;
                    end if;

                when PREP_STATUS =>
                    status_word := (others => '0');
                    status_word(0) := accelerator_busy;
                    status_word(1) := accelerator_done;
                    tx_word_reg <= status_word;
                    tx_index    <= 0;
                    state       <= SEND_WORD;

                when PREP_COUNTER =>
                    case counter_index is
                        when 0 =>
                            tx_word_reg <= low32(perf_total_cycles);
                        when 1 =>
                            tx_word_reg <= low32(perf_load_cycles);
                        when 2 =>
                            tx_word_reg <= low32(perf_compute_cycles);
                        when 3 =>
                            tx_word_reg <= low32(perf_store_cycles);
                        when 4 =>
                            tx_word_reg <= low32(perf_num_tiles_processed);
                        when others =>
                            tx_word_reg <= low32(perf_num_mac_ops_issued);
                    end case;

                    tx_index <= 0;
                    state    <= SEND_WORD;

                when SEND_ACK =>
                    if tx_busy = '0' then
                        tx_byte_reg  <= RESP_ACK;
                        tx_start_reg <= '1';
                        state        <= IDLE;
                    end if;

                when SEND_NAK =>
                    if tx_busy = '0' then
                        tx_byte_reg  <= RESP_NAK;
                        tx_start_reg <= '1';
                        state        <= IDLE;
                    end if;

                when SEND_WORD =>
                    if tx_busy = '0' then
                        case tx_index is
                            when 0 =>
                                tx_byte_reg <= tx_word_reg(31 downto 24);
                            when 1 =>
                                tx_byte_reg <= tx_word_reg(23 downto 16);
                            when 2 =>
                                tx_byte_reg <= tx_word_reg(15 downto 8);
                            when others =>
                                tx_byte_reg <= tx_word_reg(7 downto 0);
                        end case;

                        tx_start_reg <= '1';

                        if tx_index = 3 then
                            tx_index <= 0;

                            if opcode_reg = CMD_READ_COUNTERS and counter_index < 5 then
                                counter_index <= counter_index + 1;
                                state         <= PREP_COUNTER;
                            else
                                state <= IDLE;
                            end if;
                        else
                            tx_index <= tx_index + 1;
                        end if;
                    end if;
            end case;
        end if;
    end process;

end architecture rtl;
