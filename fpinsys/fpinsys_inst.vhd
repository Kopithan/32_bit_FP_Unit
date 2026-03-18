	component fpinsys is
		port (
			source : out std_logic_vector(65 downto 0);                    -- source
			probe  : in  std_logic_vector(31 downto 0) := (others => 'X')  -- probe
		);
	end component fpinsys;

	u0 : component fpinsys
		port map (
			source => CONNECTED_TO_source, -- sources.source
			probe  => CONNECTED_TO_probe   --  probes.probe
		);

