library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity uart_protocol is
    port (
        clk : in std_logic;
        rst : in std_logic;

        rx_valid : in std_logic;
        rx_byte  : in std_logic_vector(7 downto 0);

        tx_busy  : in std_logic;
        tx_start : out std_logic;
        tx_byte  : out std_logic_vector(7 downto 0);

        accelerator_busy : in std_logic;
        accelerator_done : in std_logic;
        start_pulse      : out std_logic
    );
end entity uart_protocol;

architecture rtl of uart_protocol is

    constant CMD_START  : std_logic_vector(7 downto 0) := x"53";
    constant CMD_STATUS : std_logic_vector(7 downto 0) := x"3F";
    constant RESP_DONE  : std_logic_vector(7 downto 0) := x"44";
    constant RESP_BUSY  : std_logic_vector(7 downto 0) := x"42";
    constant RESP_IDLE  : std_logic_vector(7 downto 0) := x"49";

    signal tx_start_reg : std_logic := '0';
    signal tx_byte_reg  : std_logic_vector(7 downto 0) := (others => '0');
    signal start_reg    : std_logic := '0';
    signal done_d       : std_logic := '0';

begin

    tx_start   <= tx_start_reg;
    tx_byte    <= tx_byte_reg;
    start_pulse <= start_reg;

    process(clk, rst)
    begin
        if rst = '1' then
            tx_start_reg <= '0';
            tx_byte_reg  <= (others => '0');
            start_reg    <= '0';
            done_d       <= '0';

        elsif rising_edge(clk) then
            tx_start_reg <= '0';
            start_reg    <= '0';
            done_d       <= accelerator_done;

            if rx_valid = '1' then
                if rx_byte = CMD_START then
                    start_reg <= '1';
                elsif rx_byte = CMD_STATUS and tx_busy = '0' then
                    tx_start_reg <= '1';

                    if accelerator_busy = '1' then
                        tx_byte_reg <= RESP_BUSY;
                    else
                        tx_byte_reg <= RESP_IDLE;
                    end if;
                end if;
            elsif accelerator_done = '1' and done_d = '0' and tx_busy = '0' then
                tx_start_reg <= '1';
                tx_byte_reg  <= RESP_DONE;
            end if;
        end if;
    end process;

end architecture rtl;
