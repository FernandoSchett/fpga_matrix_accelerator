library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity uart_rx is
    generic (
        CLKS_PER_BIT : positive := 434
    );
    port (
        clk       : in std_logic;
        rst       : in std_logic;
        rx_serial : in std_logic;
        rx_valid  : out std_logic;
        rx_byte   : out std_logic_vector(7 downto 0)
    );
end entity uart_rx;

architecture rtl of uart_rx is

    type state_t is (
        IDLE,
        START_BIT,
        DATA_BITS,
        STOP_BIT,
        CLEANUP
    );

    signal state : state_t := IDLE;

    signal clk_count : integer range 0 to CLKS_PER_BIT-1 := 0;
    signal bit_index : integer range 0 to 7 := 0;

    signal rx_byte_reg  : std_logic_vector(7 downto 0) := (others => '0');
    signal rx_valid_reg : std_logic := '0';

    -- Sincronizador para entrada assíncrona vinda do USB-serial.
    signal rx_meta : std_logic := '1';
    signal rx_sync : std_logic := '1';

begin

    rx_valid <= rx_valid_reg;
    rx_byte  <= rx_byte_reg;

    process(clk, rst)
    begin
        if rst = '1' then
            rx_meta <= '1';
            rx_sync <= '1';

        elsif rising_edge(clk) then
            rx_meta <= rx_serial;
            rx_sync <= rx_meta;
        end if;
    end process;

    process(clk, rst)
    begin
        if rst = '1' then
            state        <= IDLE;
            clk_count    <= 0;
            bit_index    <= 0;
            rx_byte_reg  <= (others => '0');
            rx_valid_reg <= '0';

        elsif rising_edge(clk) then
            rx_valid_reg <= '0';

            case state is

                when IDLE =>
                    clk_count <= 0;
                    bit_index <= 0;

                    if rx_sync = '0' then
                        state <= START_BIT;
                    end if;

                when START_BIT =>
                    -- Amostra no meio do start bit.
                    if clk_count = (CLKS_PER_BIT - 1) / 2 then
                        if rx_sync = '0' then
                            clk_count <= 0;
                            state     <= DATA_BITS;
                        else
                            state <= IDLE;
                        end if;
                    else
                        clk_count <= clk_count + 1;
                    end if;

                when DATA_BITS =>
                    if clk_count = CLKS_PER_BIT-1 then
                        clk_count <= 0;
                        rx_byte_reg(bit_index) <= rx_sync;

                        if bit_index = 7 then
                            bit_index <= 0;
                            state     <= STOP_BIT;
                        else
                            bit_index <= bit_index + 1;
                        end if;
                    else
                        clk_count <= clk_count + 1;
                    end if;

                when STOP_BIT =>
                    if clk_count = CLKS_PER_BIT-1 then
                        clk_count <= 0;

                        -- Só aceita o byte se o stop bit estiver alto.
                        if rx_sync = '1' then
                            rx_valid_reg <= '1';
                        end if;

                        state <= CLEANUP;
                    else
                        clk_count <= clk_count + 1;
                    end if;

                when CLEANUP =>
                    state <= IDLE;

            end case;
        end if;
    end process;

end architecture rtl;