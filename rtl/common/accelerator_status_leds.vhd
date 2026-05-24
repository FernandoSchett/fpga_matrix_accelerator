library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity accelerator_status_leds is
    generic (
        CLK_FREQ_HZ              : positive := 50000000;
        HEARTBEAT_HZ             : positive := 1;
        ACTIVITY_BLINK_HZ        : positive := 4;
        PULSE_STRETCH_CYCLES     : natural  := 12500000;
        USE_EXTERNAL_TILE_COUNTER : boolean := true
    );
    port (
        clk : in std_logic;
        rst : in std_logic;

        start          : in std_logic;
        busy           : in std_logic;
        done           : in std_logic;
        load_active    : in std_logic;
        compute_active : in std_logic;
        store_active   : in std_logic;
        tile_done      : in std_logic;
        error          : in std_logic;

        tiles_processed : in unsigned(31 downto 0);

        leds : out std_logic_vector(9 downto 0)
    );
end entity accelerator_status_leds;

architecture rtl of accelerator_status_leds is

    function div_or_one(
        constant numerator   : positive;
        constant denominator : positive
    ) return positive is
        variable result : natural;
    begin
        result := numerator / denominator;

        if result < 1 then
            return 1;
        end if;

        return result;
    end function;

    constant HEARTBEAT_TOGGLE_CYCLES : positive := div_or_one(CLK_FREQ_HZ, 2 * HEARTBEAT_HZ);
    constant ACTIVITY_TOGGLE_CYCLES  : positive := div_or_one(CLK_FREQ_HZ, 2 * ACTIVITY_BLINK_HZ);

    signal heartbeat_count : natural range 0 to HEARTBEAT_TOGGLE_CYCLES-1 := 0;
    signal activity_count  : natural range 0 to ACTIVITY_TOGGLE_CYCLES-1 := 0;

    signal heartbeat_reg : std_logic := '0';
    signal activity_blink_reg : std_logic := '0';

    signal compute_stretch_count : natural range 0 to PULSE_STRETCH_CYCLES := 0;
    signal memory_stretch_count  : natural range 0 to PULSE_STRETCH_CYCLES := 0;

    signal internal_tile_counter : unsigned(31 downto 0) := (others => '0');
    signal tile_done_d : std_logic := '0';

    signal done_latched_reg  : std_logic := '0';
    signal error_latched_reg : std_logic := '0';

    signal memory_active : std_logic;
    signal compute_visible : std_logic;
    signal memory_visible  : std_logic;
    signal progress_nibble : unsigned(3 downto 0);

begin

    memory_active <= load_active or store_active;
    compute_visible <= '1' when compute_active = '1' or compute_stretch_count /= 0 else '0';
    memory_visible  <= '1' when memory_active = '1' or memory_stretch_count /= 0 else '0';

    progress_nibble <= tiles_processed(3 downto 0) when USE_EXTERNAL_TILE_COUNTER else
                       internal_tile_counter(3 downto 0);

    leds(0) <= heartbeat_reg;
    leds(1) <= busy and activity_blink_reg;
    leds(2) <= compute_visible and activity_blink_reg;
    leds(3) <= memory_visible and activity_blink_reg;
    leds(7 downto 4) <= std_logic_vector(progress_nibble);
    leds(8) <= done_latched_reg;
    leds(9) <= error_latched_reg;

    process(clk, rst)
    begin
        if rst = '1' then
            heartbeat_count <= 0;
            activity_count <= 0;
            heartbeat_reg <= '0';
            activity_blink_reg <= '0';
            compute_stretch_count <= 0;
            memory_stretch_count <= 0;
            internal_tile_counter <= (others => '0');
            tile_done_d <= '0';
            done_latched_reg <= '0';
            error_latched_reg <= '0';

        elsif rising_edge(clk) then
            tile_done_d <= tile_done;

            if heartbeat_count = HEARTBEAT_TOGGLE_CYCLES-1 then
                heartbeat_count <= 0;
                heartbeat_reg <= not heartbeat_reg;
            else
                heartbeat_count <= heartbeat_count + 1;
            end if;

            if activity_count = ACTIVITY_TOGGLE_CYCLES-1 then
                activity_count <= 0;
                activity_blink_reg <= not activity_blink_reg;
            else
                activity_count <= activity_count + 1;
            end if;

            if compute_active = '1' then
                compute_stretch_count <= PULSE_STRETCH_CYCLES;
            elsif compute_stretch_count /= 0 then
                compute_stretch_count <= compute_stretch_count - 1;
            end if;

            if memory_active = '1' then
                memory_stretch_count <= PULSE_STRETCH_CYCLES;
            elsif memory_stretch_count /= 0 then
                memory_stretch_count <= memory_stretch_count - 1;
            end if;

            if start = '1' then
                internal_tile_counter <= (others => '0');
                done_latched_reg <= '0';
            elsif tile_done = '1' and tile_done_d = '0' then
                internal_tile_counter <= internal_tile_counter + 1;
            end if;

            if done = '1' then
                done_latched_reg <= '1';
            end if;

            if error = '1' then
                error_latched_reg <= '1';
            end if;
        end if;
    end process;

end architecture rtl;
