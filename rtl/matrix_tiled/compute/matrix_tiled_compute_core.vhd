library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity matrix_tiled_compute_core is
    generic (
        TILE_SIZE  : positive := 4;
        NUM_MACS   : positive := 4;
        DATA_WIDTH : positive := 8;
        ACC_WIDTH  : positive := 32
    );
    port (
        clk : in std_logic;
        rst : in std_logic;

        start : in std_logic;
        done  : out std_logic;

        a_tile      : in std_logic_vector((TILE_SIZE*TILE_SIZE*DATA_WIDTH)-1 downto 0);
        b_tile      : in std_logic_vector((TILE_SIZE*TILE_SIZE*DATA_WIDTH)-1 downto 0);
        c_tile_in   : in std_logic_vector((TILE_SIZE*TILE_SIZE*ACC_WIDTH)-1 downto 0);
        c_tile_out  : out std_logic_vector((TILE_SIZE*TILE_SIZE*ACC_WIDTH)-1 downto 0)
    );
end entity matrix_tiled_compute_core;

architecture rtl of matrix_tiled_compute_core is

    constant TILE_ELEMS : positive := TILE_SIZE * TILE_SIZE;

    subtype data_t is signed(DATA_WIDTH-1 downto 0);
    subtype acc_t  is signed(ACC_WIDTH-1 downto 0);

    type acc_tile_t is array (0 to TILE_ELEMS-1) of acc_t;
    type data_lane_t is array (0 to NUM_MACS-1) of data_t;
    type acc_lane_t is array (0 to NUM_MACS-1) of acc_t;

    type state_t is (
        IDLE,
        RUN,
        DONE_STATE
    );

    signal state : state_t := IDLE;

    signal c_acc : acc_tile_t := (others => (others => '0'));

    signal k_idx     : integer range 0 to TILE_SIZE-1 := 0;
    signal elem_base : integer range 0 to TILE_ELEMS-1 := 0;

    signal lane_a       : data_lane_t := (others => (others => '0'));
    signal lane_b       : data_lane_t := (others => (others => '0'));
    signal lane_acc_in  : acc_lane_t := (others => (others => '0'));
    signal lane_acc_out : acc_lane_t;

    signal done_reg : std_logic := '0';

    function get_data(
        constant flat : std_logic_vector;
        constant idx  : natural
    ) return data_t is
        variable result : data_t;
        variable left_i : natural;
    begin
        left_i := ((idx + 1) * DATA_WIDTH) - 1;
        result := signed(flat(left_i downto left_i - DATA_WIDTH + 1));
        return result;
    end function;

    function get_acc(
        constant flat : std_logic_vector;
        constant idx  : natural
    ) return acc_t is
        variable result : acc_t;
        variable left_i : natural;
    begin
        left_i := ((idx + 1) * ACC_WIDTH) - 1;
        result := signed(flat(left_i downto left_i - ACC_WIDTH + 1));
        return result;
    end function;

    function pack_acc_tile(constant tile : acc_tile_t) return std_logic_vector is
        variable result : std_logic_vector((TILE_ELEMS*ACC_WIDTH)-1 downto 0);
        variable left_i : natural;
    begin
        for idx in 0 to TILE_ELEMS-1 loop
            left_i := ((idx + 1) * ACC_WIDTH) - 1;
            result(left_i downto left_i - ACC_WIDTH + 1) := std_logic_vector(tile(idx));
        end loop;

        return result;
    end function;

begin

    done <= done_reg;
    c_tile_out <= pack_acc_tile(c_acc);

    gen_lanes : for lane in 0 to NUM_MACS-1 generate
    begin
        process(state, elem_base, k_idx, a_tile, b_tile, c_acc)
            variable out_idx : integer;
            variable row_idx : integer;
            variable col_idx : integer;
        begin
            out_idx := elem_base + lane;

            if state = RUN and out_idx < TILE_ELEMS then
                row_idx := out_idx / TILE_SIZE;
                col_idx := out_idx mod TILE_SIZE;

                lane_a(lane)      <= get_data(a_tile, row_idx * TILE_SIZE + k_idx);
                lane_b(lane)      <= get_data(b_tile, k_idx * TILE_SIZE + col_idx);
                lane_acc_in(lane) <= c_acc(out_idx);
            else
                lane_a(lane)      <= (others => '0');
                lane_b(lane)      <= (others => '0');
                lane_acc_in(lane) <= (others => '0');
            end if;
        end process;

        u_mac : entity work.mac_unit
            generic map (
                DATA_WIDTH => DATA_WIDTH,
                ACC_WIDTH  => ACC_WIDTH
            )
            port map (
                a       => lane_a(lane),
                b       => lane_b(lane),
                acc_in  => lane_acc_in(lane),
                acc_out => lane_acc_out(lane)
            );
    end generate;

    process(clk, rst)
        variable out_idx : integer;
    begin
        if rst = '1' then
            state     <= IDLE;
            c_acc     <= (others => (others => '0'));
            k_idx     <= 0;
            elem_base <= 0;
            done_reg  <= '0';

        elsif rising_edge(clk) then
            case state is

                when IDLE =>
                    done_reg  <= '0';
                    k_idx     <= 0;
                    elem_base <= 0;

                    if start = '1' then
                        for idx in 0 to TILE_ELEMS-1 loop
                            c_acc(idx) <= get_acc(c_tile_in, idx);
                        end loop;

                        state <= RUN;
                    end if;

                when RUN =>
                    for lane in 0 to NUM_MACS-1 loop
                        out_idx := elem_base + lane;

                        if out_idx < TILE_ELEMS then
                            c_acc(out_idx) <= lane_acc_out(lane);
                        end if;
                    end loop;

                    if elem_base + NUM_MACS >= TILE_ELEMS then
                        elem_base <= 0;

                        if k_idx = TILE_SIZE-1 then
                            done_reg <= '1';
                            state    <= DONE_STATE;
                        else
                            k_idx <= k_idx + 1;
                        end if;
                    else
                        elem_base <= elem_base + NUM_MACS;
                    end if;

                when DONE_STATE =>
                    done_reg <= '1';

                    if start = '0' then
                        state <= IDLE;
                    end if;

            end case;
        end if;
    end process;

end architecture rtl;
