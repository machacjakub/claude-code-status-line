# Claude Code statusline — native jq (Mac/Linux). Reads session JSON on stdin.
# Run with: jq -rf statusline.jq

# --- number formatting ---
def oneDec:                                   # 1.0 -> "1.0"
  (. * 10 | round) as $x | ($x / 10)
  | if . == floor then (tostring + ".0") else tostring end;

def fmtTok:                                    # 1234567 -> "1.2M", 12345 -> "12k"
  if . == null then "?"
  elif . >= 1000000 then ((. / 1000000) | oneDec) + "M"
  elif . >= 1000    then ((. / 1000) | round | tostring) + "k"
  else (round | tostring) end;

def twoDec:                                    # 12.5 -> "12.50"
  (. * 100 | round) as $c
  | ($c / 100 | floor | tostring) as $int
  | ($c % 100) as $frac
  | $int + "." + (if $frac < 10 then "0" else "" end) + ($frac | tostring);

def rep($s; $n): if $n > 0 then ($s * $n) else "" end;

# --- ANSI color ---
# c wraps a string in a color code; heat picks green/yellow/red by a 0-100 value.
def c($code): "[" + $code + "m" + . + "[0m";
def heatCtx:  if . >= 75 then "31" elif . >= 40 then "33" else "32" end;   # context usage
def heatDay:  if . >= 85 then "31" elif . >= 50 then "33" else "32" end;   # daily (5h) usage
def heatWeek: if . >= 90 then "31" elif . >= 65 then "33" else "32" end;   # weekly (7d) usage
def costHeat: if . >= 20 then "31" elif . >= 5 then "33" elif . >= 1 then "32" else "90" end;

# colored 10-cell gauge bar from a 0-100 value: filled part in given heat color, empty part dim
def gauge($hc):
  . as $p
  | ([10, ([0, (($p / 10) | round)] | max)] | min) as $filled
  | (rep("█"; $filled) | c($hc)) + (rep("░"; 10 - $filled) | c("90"));

# color constants
"1;36" as $C_MODEL     # bold cyan
| "36"  as $C_DIR      # cyan
| "90"  as $C_DIM      # gray (separators + secondary info)

| . as $d

# --- Model (strip trailing "(...)" note, e.g. "Opus 4.8 (1M context)" -> "Opus 4.8") ---
| ((($d.model.display_name // "Claude") | sub(" *[(].*$"; "")) | c($C_MODEL)) as $model

# --- Current directory (last folder) ---
| ($d.workspace.current_dir // "") as $cwd
| ((if $cwd == "" then "?" else ($cwd | sub(".*/"; "")) end) | c($C_DIR)) as $dir

# --- Context usage: % + gauge + used/total ---
| $d.context_window as $cw
| (
    if $cw == null then ("-" | c($C_DIM))
    else
      $cw.total_input_tokens as $used
      | $cw.context_window_size as $total
      | ( $cw.used_percentage
          // (if ($used != null and (($total // 0) > 0)) then 100 * $used / $total else null end)
        ) as $pct
      | if $pct == null then ("-" | c($C_DIM))
        else
          ((($pct | round | tostring) + "%") | c($pct | heatCtx)) + " " + ($pct | gauge($pct | heatCtx))
            + (if ($used != null and $total != null)
               then (" " + ($used | fmtTok) + "/" + ($total | fmtTok) | c($C_DIM)) else "" end)
        end
    end
  ) as $ctx

# --- Token types of last turn (cache-read vs new) ---
| ($cw.current_usage) as $u
| ( if $u == null then null
    else
      (($u.cache_read_input_tokens // 0)) as $cr
      | (($u.cache_creation_input_tokens // 0) + ($u.input_tokens // 0)) as $nw
      | if ($cr + $nw) > 0 then (("cache " + ($cr | fmtTok) + " / new " + ($nw | fmtTok)) | c($C_DIM)) else null end
    end ) as $tok

# --- Rate limits (5h / 7d usage %), each colored by heat ---
| $d.rate_limits as $rl
| ( if $rl == null then null
    else
      [ (if $rl.five_hour.used_percentage != null
         then (("5h " + ($rl.five_hour.used_percentage | round | tostring) + "%") | c($rl.five_hour.used_percentage | heatDay)) + " " + ($rl.five_hour.used_percentage | gauge($rl.five_hour.used_percentage | heatDay))
         else empty end),
        (if $rl.seven_day.used_percentage != null
         then "☀️ " + (("7d " + ($rl.seven_day.used_percentage | round | tostring) + "%") | c($rl.seven_day.used_percentage | heatWeek)) + " " + ($rl.seven_day.used_percentage | gauge($rl.seven_day.used_percentage | heatWeek))
         else empty end)
      ] as $bits
      | if ($bits | length) > 0 then ($bits | join("  ")) else null end
    end ) as $rlstr

# --- Time until 5h session reset (red < 30m, yellow < 60m) ---
| ( if ($rl != null and $rl.five_hour != null and $rl.five_hour.resets_at != null)
    then
      ($rl.five_hour.resets_at - now) as $rem
      | if $rem > 0 then
          (($rem / 3600) | floor) as $h
          | ((($rem % 3600) / 60) | floor) as $m
          | (($h | tostring) + "h " + ($m | tostring) + "m to reset")
            | c(if $rem < 1800 then "31" elif $rem < 3600 then "33" else "90" end)
        else ("reset now" | c("31")) end
    else null end ) as $reset

# --- Cost (colored by magnitude) ---
| ( if ($d.cost.total_cost_usd != null)
    then (("$" + ($d.cost.total_cost_usd | twoDec)) | c($d.cost.total_cost_usd | costHeat))
    else ("$0.00" | c($C_DIM)) end ) as $cost

# --- Lines added/removed (green / red) ---
| ( if ($d.cost.total_lines_added != null or $d.cost.total_lines_removed != null)
    then (("+" + (($d.cost.total_lines_added // 0) | tostring)) | c("32"))
         + "/" + (("-" + (($d.cost.total_lines_removed // 0) | tostring)) | c("31"))
    else null end ) as $lines

# --- Session duration ---
| ( if ($d.cost.total_duration_ms != null)
    then ((($d.cost.total_duration_ms / 60000) | oneDec) + "m" | c($C_DIM))
    else null end ) as $dur

# --- Assemble (dim separator) ---
| (" · " | c($C_DIM)) as $sep
| [ "✦ " + $model,
    "📁 " + $dir,
    "🧠 " + $ctx,
    (if $rlstr != null then "⏱ " + $rlstr else empty end),
    (if $reset != null then "🔄 " + $reset else empty end),
    "💰 " + $cost,
    (if $lines != null then "📝 " + $lines else empty end)
  ] | join($sep)
