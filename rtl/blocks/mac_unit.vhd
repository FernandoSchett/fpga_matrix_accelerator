library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity mac_unit is
    generic (
        DATA_WIDTH : integer := 16;
        ACC_WIDTH  : integer := 32
    );
    port (
        a       : in  signed(DATA_WIDTH-1 downto 0);
        b       : in  signed(DATA_WIDTH-1 downto 0);
        acc_in  : in  signed(ACC_WIDTH-1 downto 0);
        acc_out : out signed(ACC_WIDTH-1 downto 0)
    );
end entity mac_unit;

architecture rtl of mac_unit is
    signal product : signed((2*DATA_WIDTH)-1 downto 0);
begin

    product <= a * b;

    acc_out <= acc_in + resize(product, ACC_WIDTH);

end architecture rtl;
