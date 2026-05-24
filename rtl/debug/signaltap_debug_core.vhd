library ieee;
use ieee.std_logic_1164.all;

entity signaltap_debug_core is
    generic (
        DATA_BITS       : positive := 128;
        TRIGGER_BITS    : positive := 8;
        SAMPLE_DEPTH    : positive := 512;
        MEM_ADDR_BITS   : positive := 9;
        DATA_CNTR_BITS  : positive := 7
    );
    port (
        clk          : in std_logic;
        probe_data   : in std_logic_vector(DATA_BITS-1 downto 0);
        trigger_data : in std_logic_vector(TRIGGER_BITS-1 downto 0)
    );
end entity signaltap_debug_core;

architecture rtl of signaltap_debug_core is

    component sld_signaltap
        generic (
            SLD_DATA_BITS          : natural := 1;
            SLD_TRIGGER_BITS       : natural := 1;
            SLD_SAMPLE_DEPTH       : natural := 16;
            SLD_MEM_ADDRESS_BITS   : natural := 7;
            SLD_DATA_BIT_CNTR_BITS : natural := 4;
            SLD_RAM_BLOCK_TYPE     : string := "AUTO";
            SLD_BUFFER_FULL_STOP   : natural := 1;
            SLD_TRIGGER_LEVEL      : natural := 1;
            SLD_SECTION_ID         : string := "hdl_signaltap_0";
            lpm_type               : string := "sld_signaltap"
        );
        port (
            acq_clk         : in std_logic;
            clr             : in std_logic := '0';
            clrn            : in std_logic := '1';
            ena             : in std_logic := '1';
            storage_enable  : in std_logic := '1';
            acq_data_in     : in std_logic_vector(SLD_DATA_BITS-1 downto 0);
            acq_trigger_in  : in std_logic_vector(SLD_TRIGGER_BITS-1 downto 0);
            acq_trigger_out : out std_logic_vector(SLD_TRIGGER_BITS-1 downto 0);
            acq_data_out    : out std_logic_vector(SLD_DATA_BITS-1 downto 0);
            trigger_out     : out std_logic;
            gnd             : out std_logic;
            vcc             : out std_logic;
            irq             : out std_logic;
            tdo             : out std_logic
        );
    end component;

    signal acq_trigger_out_unused : std_logic_vector(TRIGGER_BITS-1 downto 0);
    signal acq_data_out_unused    : std_logic_vector(DATA_BITS-1 downto 0);
    signal trigger_out_unused     : std_logic;
    signal gnd_unused             : std_logic;
    signal vcc_unused             : std_logic;
    signal irq_unused             : std_logic;
    signal tdo_unused             : std_logic;

    attribute keep : boolean;
    attribute preserve : boolean;
    attribute keep of probe_data : signal is true;
    attribute keep of trigger_data : signal is true;
    attribute preserve of probe_data : signal is true;
    attribute preserve of trigger_data : signal is true;

begin

    u_signaltap : sld_signaltap
        generic map (
            SLD_DATA_BITS          => DATA_BITS,
            SLD_TRIGGER_BITS       => TRIGGER_BITS,
            SLD_SAMPLE_DEPTH       => SAMPLE_DEPTH,
            SLD_MEM_ADDRESS_BITS   => MEM_ADDR_BITS,
            SLD_DATA_BIT_CNTR_BITS => DATA_CNTR_BITS,
            SLD_RAM_BLOCK_TYPE     => "M10K",
            SLD_BUFFER_FULL_STOP   => 1,
            SLD_TRIGGER_LEVEL      => 1,
            SLD_SECTION_ID         => "matrix_accel_signaltap",
            lpm_type               => "sld_signaltap"
        )
        port map (
            acq_clk         => clk,
            clr             => '0',
            clrn            => '1',
            ena             => '1',
            storage_enable  => '1',
            acq_data_in     => probe_data,
            acq_trigger_in  => trigger_data,
            acq_trigger_out => acq_trigger_out_unused,
            acq_data_out    => acq_data_out_unused,
            trigger_out     => trigger_out_unused,
            gnd             => gnd_unused,
            vcc             => vcc_unused,
            irq             => irq_unused,
            tdo             => tdo_unused
        );

end architecture rtl;
