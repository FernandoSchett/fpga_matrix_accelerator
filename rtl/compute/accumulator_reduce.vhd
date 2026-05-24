library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity accumulator_reduce is
    generic (
        NUM_INPUTS : positive := 4;
        ACC_WIDTH  : positive := 32
    );
    port (
        values_in : in  std_logic_vector((NUM_INPUTS*ACC_WIDTH)-1 downto 0);
        sum_out   : out signed(ACC_WIDTH-1 downto 0)
    );
end entity accumulator_reduce;

architecture rtl of accumulator_reduce is
begin

    process(values_in)
        variable total : signed(ACC_WIDTH-1 downto 0);
        variable value : signed(ACC_WIDTH-1 downto 0);
        variable lsb   : natural;
        variable msb   : natural;
    begin
        total := (others => '0');

        for idx in 0 to NUM_INPUTS-1 loop
            lsb := idx * ACC_WIDTH;
            msb := ((idx + 1) * ACC_WIDTH) - 1;
            value := signed(values_in(msb downto lsb));
            total := total + value;
        end loop;

        sum_out <= total;
    end process;

end architecture rtl;
