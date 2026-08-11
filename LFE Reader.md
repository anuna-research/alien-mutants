# LFE Reader

The `lfe` OTP application's own front end for turning `.lfe` source text into
parsed forms (`lfe_io:read_file/1` and related functions). [[SPEC-001-lfe-mutation-testing#CON-001]]
requires alien-mutants to read source exclusively through this reader rather
than a hand-rolled parser.
