library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.matrix_tiled_pkg.all;

entity tile_buffered_compute_engine is
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

        a_rd_row_flat  : out std_logic_vector((NUM_MACS*clog2(TILE_SIZE))-1 downto 0);
        a_rd_col_flat  : out std_logic_vector((NUM_MACS*clog2(TILE_SIZE))-1 downto 0);
        a_rd_data_flat : in  std_logic_vector((NUM_MACS*DATA_WIDTH)-1 downto 0);

        b_rd_row_flat  : out std_logic_vector((NUM_MACS*clog2(TILE_SIZE))-1 downto 0);
        b_rd_col_flat  : out std_logic_vector((NUM_MACS*clog2(TILE_SIZE))-1 downto 0);
        b_rd_data_flat : in  std_logic_vector((NUM_MACS*DATA_WIDTH)-1 downto 0);

        c_rd_row  : out unsigned(clog2(TILE_SIZE)-1 downto 0);
        c_rd_col  : out unsigned(clog2(TILE_SIZE)-1 downto 0);
        c_rd_data : in  signed(ACC_WIDTH-1 downto 0);

        c_wr_en   : out std_logic;
        c_wr_row  : out unsigned(clog2(TILE_SIZE)-1 downto 0);
        c_wr_col  : out unsigned(clog2(TILE_SIZE)-1 downto 0);
        c_wr_data : out signed(ACC_WIDTH-1 downto 0);

        mac_ops_issued : out unsigned(31 downto 0)
    );
end entity tile_buffered_compute_engine;

architecture rtl of tile_buffered_compute_engine is

    constant LOCAL_W    : positive := clog2(TILE_SIZE);
    constant TILE_ELEMS : positive := TILE_SIZE * TILE_SIZE;

    subtype acc_t is signed(ACC_WIDTH-1 downto 0);
    type acc_tile_t is array (0 to TILE_ELEMS-1) of acc_t;

    type state_t is (
        IDLE,
        LOAD_C_ADDR,
        LOAD_C_WAIT,
        LOAD_C_CAPTURE,
        RUN_ADDR,
        RUN_WAIT,
        RUN_MAC,
        WRITE_C,
        DONE_STATE
    );

    signal state : state_t := IDLE;

    signal c_acc : acc_tile_t := (others => (others => '0'));
    signal c_idx : natural range 0 to TILE_ELEMS-1 := 0;
    signal k_idx : natural range 0 to TILE_SIZE-1 := 0;
    signal elem_base : natural range 0 to TILE_ELEMS-1 := 0;

    signal done_reg : std_logic := '0';
    signal c_wr_en_reg : std_logic := '0';
    signal c_rd_row_reg : unsigned(LOCAL_W-1 downto 0) := (others => '0');
    signal c_rd_col_reg : unsigned(LOCAL_W-1 downto 0) := (others => '0');
    signal c_wr_row_reg : unsigned(LOCAL_W-1 downto 0) := (others => '0');
    signal c_wr_col_reg : unsigned(LOCAL_W-1 downto 0) := (others => '0');
    signal c_wr_data_reg : acc_t := (others => '0');
    signal mac_ops_issued_reg : unsigned(31 downto 0) := (others => '0');

    function local_row(idx : natural) return natural is
    begin
        return idx / TILE_SIZE;
    end function;

    function local_col(idx : natural) return natural is
    begin
        return idx mod TILE_SIZE;
    end function;

    function lane_data(
        constant flat : std_logic_vector;
        constant lane : natural
    ) return signed is
        variable left_i : natural;
    begin
        left_i := ((lane + 1) * DATA_WIDTH) - 1;
        return signed(flat(left_i downto left_i - DATA_WIDTH + 1));
    end function;

begin

    done <= done_reg;
    c_wr_en <= c_wr_en_reg;
    c_rd_row <= c_rd_row_reg;
    c_rd_col <= c_rd_col_reg;
    c_wr_row <= c_wr_row_reg;
    c_wr_col <= c_wr_col_reg;
    c_wr_data <= c_wr_data_reg;
    mac_ops_issued <= mac_ops_issued_reg;

    process(state, elem_base, k_idx)
        variable a_rows : std_logic_vector((NUM_MACS*LOCAL_W)-1 downto 0);
        variable a_cols : std_logic_vector((NUM_MACS*LOCAL_W)-1 downto 0);
        variable b_rows : std_logic_vector((NUM_MACS*LOCAL_W)-1 downto 0);
        variable b_cols : std_logic_vector((NUM_MACS*LOCAL_W)-1 downto 0);
        variable out_idx : natural;
        variable row_idx : natural;
        variable col_idx : natural;
        variable left_i : natural;
    begin
        a_rows := (others => '0');
        a_cols := (others => '0');
        b_rows := (others => '0');
        b_cols := (others => '0');

        if state = RUN_ADDR or state = RUN_WAIT or state = RUN_MAC then
            for lane in 0 to NUM_MACS-1 loop
                out_idx := elem_base + lane;

                if out_idx < TILE_ELEMS then
                    row_idx := local_row(out_idx);
                    col_idx := local_col(out_idx);
                    left_i := ((lane + 1) * LOCAL_W) - 1;

                    a_rows(left_i downto left_i - LOCAL_W + 1) :=
                        std_logic_vector(to_unsigned(row_idx, LOCAL_W));
                    a_cols(left_i downto left_i - LOCAL_W + 1) :=
                        std_logic_vector(to_unsigned(k_idx, LOCAL_W));
                    b_rows(left_i downto left_i - LOCAL_W + 1) :=
                        std_logic_vector(to_unsigned(k_idx, LOCAL_W));
                    b_cols(left_i downto left_i - LOCAL_W + 1) :=
                        std_logic_vector(to_unsigned(col_idx, LOCAL_W));
                end if;
            end loop;
        end if;

        a_rd_row_flat <= a_rows;
        a_rd_col_flat <= a_cols;
        b_rd_row_flat <= b_rows;
        b_rd_col_flat <= b_cols;
    end process;

    process(clk, rst)
        variable out_idx : natural;
        variable product : signed((2*DATA_WIDTH)-1 downto 0);
        variable issued  : natural;
    begin
        if rst = '1' then
            state <= IDLE;
            c_acc <= (others => (others => '0'));
            c_idx <= 0;
            k_idx <= 0;
            elem_base <= 0;
            done_reg <= '0';
            c_wr_en_reg <= '0';
            c_rd_row_reg <= (others => '0');
            c_rd_col_reg <= (others => '0');
            c_wr_row_reg <= (others => '0');
            c_wr_col_reg <= (others => '0');
            c_wr_data_reg <= (others => '0');
            mac_ops_issued_reg <= (others => '0');

        elsif rising_edge(clk) then
            done_reg <= '0';
            c_wr_en_reg <= '0';
            mac_ops_issued_reg <= (others => '0');

            case state is
                when IDLE =>
                    c_idx <= 0;
                    k_idx <= 0;
                    elem_base <= 0;
                    if start = '1' then
                        state <= LOAD_C_ADDR;
                    end if;

                when LOAD_C_ADDR =>
                    c_rd_row_reg <= to_unsigned(local_row(c_idx), LOCAL_W);
                    c_rd_col_reg <= to_unsigned(local_col(c_idx), LOCAL_W);
                    state <= LOAD_C_WAIT;

                when LOAD_C_WAIT =>
                    state <= LOAD_C_CAPTURE;

                when LOAD_C_CAPTURE =>
                    c_acc(c_idx) <= c_rd_data;
                    if c_idx = TILE_ELEMS-1 then
                        c_idx <= 0;
                        k_idx <= 0;
                        elem_base <= 0;
                        state <= RUN_ADDR;
                    else
                        c_idx <= c_idx + 1;
                        state <= LOAD_C_ADDR;
                    end if;

                when RUN_ADDR =>
                    state <= RUN_WAIT;

                when RUN_WAIT =>
                    state <= RUN_MAC;

                when RUN_MAC =>
                    issued := 0;
                    for lane in 0 to NUM_MACS-1 loop
                        out_idx := elem_base + lane;

                        if out_idx < TILE_ELEMS then
                            product := lane_data(a_rd_data_flat, lane) *
                                       lane_data(b_rd_data_flat, lane);
                            c_acc(out_idx) <= c_acc(out_idx) + resize(product, ACC_WIDTH);
                            issued := issued + 1;
                        end if;
                    end loop;

                    mac_ops_issued_reg <= to_unsigned(issued, mac_ops_issued_reg'length);

                    if elem_base + NUM_MACS >= TILE_ELEMS then
                        elem_base <= 0;

                        if k_idx = TILE_SIZE-1 then
                            c_idx <= 0;
                            state <= WRITE_C;
                        else
                            k_idx <= k_idx + 1;
                            state <= RUN_ADDR;
                        end if;
                    else
                        elem_base <= elem_base + NUM_MACS;
                        state <= RUN_ADDR;
                    end if;

                when WRITE_C =>
                    c_wr_en_reg <= '1';
                    c_wr_row_reg <= to_unsigned(local_row(c_idx), LOCAL_W);
                    c_wr_col_reg <= to_unsigned(local_col(c_idx), LOCAL_W);
                    c_wr_data_reg <= c_acc(c_idx);

                    if c_idx = TILE_ELEMS-1 then
                        state <= DONE_STATE;
                    else
                        c_idx <= c_idx + 1;
                    end if;

                when DONE_STATE =>
                    done_reg <= '1';
                    state <= IDLE;
            end case;
        end if;
    end process;

end architecture rtl;
