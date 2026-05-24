library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity command_interface is
    port (
        clk : in std_logic;
        rst : in std_logic;

        cmd_valid  : in std_logic;
        cmd_opcode : in std_logic_vector(7 downto 0);
        cmd_arg    : in std_logic_vector(31 downto 0);

        accelerator_busy : in std_logic;
        accelerator_done : in std_logic;

        start_pulse  : out std_logic;
        clear_perf   : out std_logic;
        status_word  : out std_logic_vector(31 downto 0);
        status_valid : out std_logic
    );
end entity command_interface;

architecture rtl of command_interface is

    constant CMD_START      : std_logic_vector(7 downto 0) := x"53";
    constant CMD_CLEAR_PERF : std_logic_vector(7 downto 0) := x"43";
    constant CMD_STATUS     : std_logic_vector(7 downto 0) := x"3F";

    signal start_reg        : std_logic := '0';
    signal clear_perf_reg   : std_logic := '0';
    signal status_word_reg  : std_logic_vector(31 downto 0) := (others => '0');
    signal status_valid_reg : std_logic := '0';

begin

    start_pulse  <= start_reg;
    clear_perf   <= clear_perf_reg;
    status_word  <= status_word_reg;
    status_valid <= status_valid_reg;

    process(clk, rst)
    begin
        if rst = '1' then
            start_reg        <= '0';
            clear_perf_reg   <= '0';
            status_word_reg  <= (others => '0');
            status_valid_reg <= '0';

        elsif rising_edge(clk) then
            start_reg        <= '0';
            clear_perf_reg   <= '0';
            status_valid_reg <= '0';

            if cmd_valid = '1' then
                if cmd_opcode = CMD_START then
                    if accelerator_busy = '0' then
                        start_reg <= '1';
                    end if;
                elsif cmd_opcode = CMD_CLEAR_PERF then
                    clear_perf_reg <= '1';
                elsif cmd_opcode = CMD_STATUS then
                    status_word_reg(0) <= accelerator_busy;
                    status_word_reg(1) <= accelerator_done;
                    status_word_reg(31 downto 2) <= (others => '0');
                    status_valid_reg <= '1';
                else
                    status_word_reg <= cmd_arg;
                    status_valid_reg <= '1';
                end if;
            end if;
        end if;
    end process;

end architecture rtl;
