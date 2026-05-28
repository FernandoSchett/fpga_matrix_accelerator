library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity accelerator_status_leds is
    generic (
        CLK_FREQ_HZ               : positive := 50000000;
        HEARTBEAT_HZ              : positive := 1;
        ACTIVITY_BLINK_HZ         : positive := 4;
        PULSE_STRETCH_CYCLES      : natural  := 12500000;
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

    signal heartbeat_count : natural range 0 to HEARTBEAT_TOGGLE_CYCLES-1 := 0;
    signal heartbeat_reg   : std_logic := '0';

    signal start_seen_reg   : std_logic := '0';
    signal busy_seen_reg    : std_logic := '0';
    signal done_seen_reg    : std_logic := '0';
    signal load_seen_reg    : std_logic := '0';
    signal compute_seen_reg : std_logic := '0';
    signal store_seen_reg   : std_logic := '0';
    signal tile_seen_reg    : std_logic := '0';
    signal error_seen_reg   : std_logic := '0';

    signal tiles_prev       : unsigned(31 downto 0) := (others => '0');
    signal tiles_changed_reg : std_logic := '0';

begin

    -- Debug mapping:
    --
    -- LEDR[0] = heartbeat: clock/reset funcionando
    -- LEDR[1] = start chegou pelo botão ou UART
    -- LEDR[2] = busy subiu pelo menos uma vez
    -- LEDR[3] = done subiu pelo menos uma vez
    -- LEDR[4] = load_active subiu pelo menos uma vez
    -- LEDR[5] = compute_active subiu pelo menos uma vez
    -- LEDR[6] = store_active subiu pelo menos uma vez
    -- LEDR[7] = tile_done subiu pelo menos uma vez
    -- LEDR[8] = tiles_processed mudou
    -- LEDR[9] = error subiu pelo menos uma vez

    leds(0) <= heartbeat_reg;
    leds(1) <= start_seen_reg;
    leds(2) <= busy_seen_reg;
    leds(3) <= done_seen_reg;
    leds(4) <= load_seen_reg;
    leds(5) <= compute_seen_reg;
    leds(6) <= store_seen_reg;
    leds(7) <= tile_seen_reg;
    leds(8) <= tiles_changed_reg;
    leds(9) <= error_seen_reg;

    process(clk, rst)
    begin
        if rst = '1' then
            heartbeat_count <= 0;
            heartbeat_reg   <= '0';

            start_seen_reg   <= '0';
            busy_seen_reg    <= '0';
            done_seen_reg    <= '0';
            load_seen_reg    <= '0';
            compute_seen_reg <= '0';
            store_seen_reg   <= '0';
            tile_seen_reg    <= '0';
            error_seen_reg   <= '0';

            tiles_prev        <= (others => '0');
            tiles_changed_reg <= '0';

        elsif rising_edge(clk) then

            if heartbeat_count = HEARTBEAT_TOGGLE_CYCLES-1 then
                heartbeat_count <= 0;
                heartbeat_reg <= not heartbeat_reg;
            else
                heartbeat_count <= heartbeat_count + 1;
            end if;

            if start = '1' then
                start_seen_reg <= '1';
            end if;

            if busy = '1' then
                busy_seen_reg <= '1';
            end if;

            if done = '1' then
                done_seen_reg <= '1';
            end if;

            if load_active = '1' then
                load_seen_reg <= '1';
            end if;

            if compute_active = '1' then
                compute_seen_reg <= '1';
            end if;

            if store_active = '1' then
                store_seen_reg <= '1';
            end if;

            if tile_done = '1' then
                tile_seen_reg <= '1';
            end if;

            if tiles_processed /= tiles_prev then
                tiles_changed_reg <= '1';
                tiles_prev <= tiles_processed;
            end if;

            if error = '1' then
                error_seen_reg <= '1';
            end if;

        end if;
    end process;

end architecture rtl;