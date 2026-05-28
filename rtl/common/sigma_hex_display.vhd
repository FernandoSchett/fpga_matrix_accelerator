library ieee;
use ieee.std_logic_1164.all;

entity sigma_hex_display is
    port (
        running : in std_logic;

        HEX0 : out std_logic_vector(6 downto 0);
        HEX1 : out std_logic_vector(6 downto 0);
        HEX2 : out std_logic_vector(6 downto 0);
        HEX3 : out std_logic_vector(6 downto 0);
        HEX4 : out std_logic_vector(6 downto 0);
        HEX5 : out std_logic_vector(6 downto 0)
    );
end entity sigma_hex_display;

architecture rtl of sigma_hex_display is

    -- DE0-CV HEX displays are active-low.
    -- Segment order assumed by your QSF/testbench:
    -- HEXx(0) .. HEXx(6)
    --
    -- These encodings are the same ones your old testbench expected for SIGMAX:
    --
    -- HEX5 = S
    -- HEX4 = I
    -- HEX3 = G
    -- HEX2 = M
    -- HEX1 = A
    -- HEX0 = X

    constant SEG_BLANK : std_logic_vector(6 downto 0) := "1111111";

    constant SEG_S : std_logic_vector(6 downto 0) := "0010010";
    constant SEG_I : std_logic_vector(6 downto 0) := "1111001";
    constant SEG_G : std_logic_vector(6 downto 0) := "0000010";
    constant SEG_M : std_logic_vector(6 downto 0) := "0101011";
    constant SEG_A : std_logic_vector(6 downto 0) := "0001000";
    constant SEG_X : std_logic_vector(6 downto 0) := "0001001";

begin

    process(running)
    begin
        if running = '1' then
            -- Ordem física na placa:
            -- HEX5 HEX4 HEX3 HEX2 HEX1 HEX0
            --   S    I    G    M    A    X
            HEX5 <= SEG_S;
            HEX4 <= SEG_I;
            HEX3 <= SEG_G;
            HEX2 <= SEG_M;
            HEX1 <= SEG_A;
            HEX0 <= SEG_X;
        else
            HEX5 <= SEG_BLANK;
            HEX4 <= SEG_BLANK;
            HEX3 <= SEG_BLANK;
            HEX2 <= SEG_BLANK;
            HEX1 <= SEG_BLANK;
            HEX0 <= SEG_BLANK;
        end if;
    end process;

end architecture rtl;