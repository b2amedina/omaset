-- Minimal default looknfeel fixture for tests. Values differ from the real
-- Omarchy defaults so tests can assert that the fixture (not the real system)
-- is being read.

hl.config({
  general = {
    gaps_in = 3,
    gaps_out = 7,
    border_size = 1,
    layout = "dwindle",
  },
  decoration = {
    rounding = 4,
    blur = { enabled = false },
    shadow = { enabled = true },
  },
  animations = { enabled = true },
})

hl.config({
  dwindle = { force_split = 1 },
  scrolling = { column_width = 0.5 },
  master = { new_status = "slave" },
})
