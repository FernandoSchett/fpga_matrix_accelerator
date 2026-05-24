library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity matrix_single_port_ram is
    generic (
        DATA_WIDTH : positive := 8;
        ADDR_WIDTH : positive := 14;
        DEPTH      : positive := 16384
    );
    port (
        clk      : in std_logic;
        wr_en    : in std_logic;
        addr     : in unsigned(ADDR_WIDTH-1 downto 0);
        wr_data  : in signed(DATA_WIDTH-1 downto 0);
        rd_data  : out signed(DATA_WIDTH-1 downto 0)
    );
end entity matrix_single_port_ram;

architecture rtl of matrix_single_port_ram is

    type ram_t is array (0 to DEPTH-1) of std_logic_vector(DATA_WIDTH-1 downto 0);

    signal ram    : ram_t := (others => (others => '0'));
    signal rd_reg : std_logic_vector(DATA_WIDTH-1 downto 0) := (others => '0');

    attribute ramstyle : string;
    attribute ramstyle of ram : signal is "M10K";

begin

    process(clk)
        variable addr_int : integer;
    begin
        if rising_edge(clk) then
            addr_int := to_integer(addr);

            if wr_en = '1' and addr_int < DEPTH then
                ram(addr_int) <= std_logic_vector(wr_data);
            end if;

            if addr_int < DEPTH then
                rd_reg <= ram(addr_int);
            else
                rd_reg <= (others => '0');
            end if;
        end if;
    end process;

    rd_data <= signed(rd_reg);

end architecture rtl;
