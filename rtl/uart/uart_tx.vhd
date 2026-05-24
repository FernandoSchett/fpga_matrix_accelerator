library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity uart_tx is
    generic (
        CLKS_PER_BIT : positive := 434
    );
    port (
        clk       : in std_logic;
        rst       : in std_logic;
        tx_start  : in std_logic;
        tx_byte   : in std_logic_vector(7 downto 0);
        tx_serial : out std_logic;
        tx_busy   : out std_logic
    );
end entity uart_tx;

architecture rtl of uart_tx is

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
    signal tx_byte_reg : std_logic_vector(7 downto 0) := (others => '0');
    signal tx_serial_reg : std_logic := '1';
    signal tx_busy_reg : std_logic := '0';

begin

    tx_serial <= tx_serial_reg;
    tx_busy   <= tx_busy_reg;

    process(clk, rst)
    begin
        if rst = '1' then
            state         <= IDLE;
            clk_count     <= 0;
            bit_index     <= 0;
            tx_byte_reg   <= (others => '0');
            tx_serial_reg <= '1';
            tx_busy_reg   <= '0';

        elsif rising_edge(clk) then
            case state is
                when IDLE =>
                    tx_serial_reg <= '1';
                    tx_busy_reg   <= '0';
                    clk_count     <= 0;
                    bit_index     <= 0;

                    if tx_start = '1' then
                        tx_byte_reg <= tx_byte;
                        tx_busy_reg <= '1';
                        state       <= START_BIT;
                    end if;

                when START_BIT =>
                    tx_serial_reg <= '0';

                    if clk_count = CLKS_PER_BIT-1 then
                        clk_count <= 0;
                        state     <= DATA_BITS;
                    else
                        clk_count <= clk_count + 1;
                    end if;

                when DATA_BITS =>
                    tx_serial_reg <= tx_byte_reg(bit_index);

                    if clk_count = CLKS_PER_BIT-1 then
                        clk_count <= 0;

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
                    tx_serial_reg <= '1';

                    if clk_count = CLKS_PER_BIT-1 then
                        clk_count <= 0;
                        state     <= CLEANUP;
                    else
                        clk_count <= clk_count + 1;
                    end if;

                when CLEANUP =>
                    tx_busy_reg <= '0';
                    state       <= IDLE;
            end case;
        end if;
    end process;

end architecture rtl;
