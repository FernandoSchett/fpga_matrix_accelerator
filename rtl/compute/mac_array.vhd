library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity mac_array is
    generic (
        NUM_MACS   : positive := 4;
        DATA_WIDTH : positive := 8;
        ACC_WIDTH  : positive := 32
    );
    port (
        a_lanes       : in  std_logic_vector((NUM_MACS*DATA_WIDTH)-1 downto 0);
        b_lanes       : in  std_logic_vector((NUM_MACS*DATA_WIDTH)-1 downto 0);
        acc_in_lanes  : in  std_logic_vector((NUM_MACS*ACC_WIDTH)-1 downto 0);
        acc_out_lanes : out std_logic_vector((NUM_MACS*ACC_WIDTH)-1 downto 0)
    );
end entity mac_array;

architecture rtl of mac_array is

    subtype data_t is signed(DATA_WIDTH-1 downto 0);
    subtype acc_t  is signed(ACC_WIDTH-1 downto 0);

    type data_lane_t is array (0 to NUM_MACS-1) of data_t;
    type acc_lane_t is array (0 to NUM_MACS-1) of acc_t;

    signal a_lane       : data_lane_t;
    signal b_lane       : data_lane_t;
    signal acc_in_lane  : acc_lane_t;
    signal acc_out_lane : acc_lane_t;

begin

    gen_lanes : for lane in 0 to NUM_MACS-1 generate
        constant DATA_LSB : natural := lane * DATA_WIDTH;
        constant DATA_MSB : natural := ((lane + 1) * DATA_WIDTH) - 1;
        constant ACC_LSB  : natural := lane * ACC_WIDTH;
        constant ACC_MSB  : natural := ((lane + 1) * ACC_WIDTH) - 1;
    begin
        a_lane(lane)      <= signed(a_lanes(DATA_MSB downto DATA_LSB));
        b_lane(lane)      <= signed(b_lanes(DATA_MSB downto DATA_LSB));
        acc_in_lane(lane) <= signed(acc_in_lanes(ACC_MSB downto ACC_LSB));

        acc_out_lanes(ACC_MSB downto ACC_LSB) <= std_logic_vector(acc_out_lane(lane));

        u_mac : entity work.mac_unit
            generic map (
                DATA_WIDTH => DATA_WIDTH,
                ACC_WIDTH  => ACC_WIDTH
            )
            port map (
                a       => a_lane(lane),
                b       => b_lane(lane),
                acc_in  => acc_in_lane(lane),
                acc_out => acc_out_lane(lane)
            );
    end generate;

end architecture rtl;
