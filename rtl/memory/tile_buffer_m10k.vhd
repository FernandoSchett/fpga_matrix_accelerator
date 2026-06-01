library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.matrix_tiled_pkg.all;

entity tile_buffer_m10k is
    generic (
        TILE_SIZE  : positive := 16;
        DATA_WIDTH : positive := 8
    );
    port (
        clk : in std_logic;

        wr_en   : in std_logic;
        wr_row  : in unsigned(clog2(TILE_SIZE)-1 downto 0);
        wr_col  : in unsigned(clog2(TILE_SIZE)-1 downto 0);
        wr_data : in signed(DATA_WIDTH-1 downto 0);

        rd_row  : in unsigned(clog2(TILE_SIZE)-1 downto 0);
        rd_col  : in unsigned(clog2(TILE_SIZE)-1 downto 0);
        rd_data : out signed(DATA_WIDTH-1 downto 0)
    );
end entity tile_buffer_m10k;

architecture rtl of tile_buffer_m10k is

    constant DEPTH      : positive := TILE_SIZE * TILE_SIZE;
    constant ADDR_WIDTH : positive := clog2(DEPTH);

    type ram_t is array (0 to DEPTH-1) of std_logic_vector(DATA_WIDTH-1 downto 0);

    signal ram    : ram_t := (others => (others => '0'));
    signal rd_reg : std_logic_vector(DATA_WIDTH-1 downto 0) := (others => '0');

    attribute ramstyle : string;
    attribute ramstyle of ram : signal is "M10K";

    function local_addr(row_value : unsigned; col_value : unsigned) return natural is
    begin
        return (to_integer(row_value) * TILE_SIZE) + to_integer(col_value);
    end function;

begin

    process(clk)
        variable wr_index : natural;
        variable rd_index : natural;
    begin
        if rising_edge(clk) then
            wr_index := local_addr(wr_row, wr_col);
            rd_index := local_addr(rd_row, rd_col);

            if wr_en = '1' and wr_index < DEPTH then
                ram(wr_index) <= std_logic_vector(wr_data);
            end if;

            if rd_index < DEPTH then
                rd_reg <= ram(rd_index);
            else
                rd_reg <= (others => '0');
            end if;
        end if;
    end process;

    rd_data <= signed(rd_reg);

end architecture rtl;
