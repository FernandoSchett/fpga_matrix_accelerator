library ieee;
use ieee.std_logic_1164.all;
use std.env.all;

entity tb_sigma_hex_display is
end entity tb_sigma_hex_display;

architecture sim of tb_sigma_hex_display is

    signal running : std_logic := '0';
    signal HEX0    : std_logic_vector(6 downto 0);
    signal HEX1    : std_logic_vector(6 downto 0);
    signal HEX2    : std_logic_vector(6 downto 0);
    signal HEX3    : std_logic_vector(6 downto 0);
    signal HEX4    : std_logic_vector(6 downto 0);
    signal HEX5    : std_logic_vector(6 downto 0);

begin

    dut : entity work.sigma_hex_display
        port map (
            running => running,
            HEX0    => HEX0,
            HEX1    => HEX1,
            HEX2    => HEX2,
            HEX3    => HEX3,
            HEX4    => HEX4,
            HEX5    => HEX5
        );

    stim_proc : process
    begin
        wait for 1 ns;

        assert HEX0 = "1111111" and HEX1 = "1111111" and HEX2 = "1111111" and
               HEX3 = "1111111" and HEX4 = "1111111" and HEX5 = "1111111"
            report "Displays deveriam ficar apagados quando running=0."
            severity failure;

        running <= '1';
        wait for 1 ns;

        assert HEX5 = "0010010" report "HEX5 deveria mostrar S." severity failure;
        assert HEX4 = "1111001" report "HEX4 deveria mostrar I." severity failure;
        assert HEX3 = "0000010" report "HEX3 deveria mostrar G." severity failure;
        assert HEX2 = "0101011" report "HEX2 deveria mostrar M aproximado." severity failure;
        assert HEX1 = "0001000" report "HEX1 deveria mostrar A." severity failure;
        assert HEX0 = "0001001" report "HEX0 deveria mostrar X aproximado." severity failure;

        report "SIM_RESULT: PASS" severity note;
        finish;
    end process;

end architecture sim;
