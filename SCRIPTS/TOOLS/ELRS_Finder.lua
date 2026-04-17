-- finder.lua  (EdgeTX/Boxer B/W friendly)
-- ELRS/CRSF RSSI-based lost model finder (Geiger style)
-- v2 – adaptive EMA, auto-calibration, signal-loss reset, cold-start guard

local lastBeep     = 0
local avg          = -120
local minSeen      = -120
local maxSeen      = -40
local sampleCount  = 0
local calibrated   = false
local noSignalSince = nil

local function clamp(x, a, b)
  if x < a then return a elseif x > b then return b else return x end
end

local function readSignal()
  -- Prefer 1RSS (CRSF dBm), else RSNR (dB), else RQly (%)
  local rssi = getValue("1RSS")
  if type(rssi) == "number" and rssi ~= 0 then
    return clamp(rssi, -130, -20), "dBm"
  end
  local snr = getValue("RSNR")
  if type(snr) == "number" and snr ~= 0 then
    return clamp(snr * 2 - 120, -130, -20), "SNR"
  end
  local rql = getValue("RQly")
  if type(rql) == "number" and rql > 0 then
    return clamp(rql - 120, -130, -20), "LQ"
  end
  return -120, "NA"
end

local function run_func(event)
  local now = getTime()  -- 10 ms ticks
  local raw, kind = readSignal()

  -- ── Obsługa braku sygnału: reset kalibracji po 5 s ciszy ──────────────────
  if kind == "NA" then
    if not noSignalSince then noSignalSince = now end
    if now - noSignalSince > 500 then   -- 500 ticks = 5 sekund
      minSeen       = -120
      maxSeen       = -40
      avg           = -120
      sampleCount   = 0
      calibrated    = false
      noSignalSince = nil
    end
  else
    noSignalSince = nil
  end

  -- ── Adaptacyjny filtr EMA ─────────────────────────────────────────────────
  local diff  = math.abs(raw - avg)
  local alpha = clamp(diff / 50, 0.05, 0.3)
  avg = avg + alpha * (raw - avg)

  -- ── Auto-kalibracja zakresu ───────────────────────────────────────────────
  if raw > -120 then   -- tylko gdy jest prawdziwy sygnał
    if raw < minSeen then minSeen = raw end
    if raw > maxSeen then maxSeen = raw end
    sampleCount = sampleCount + 1
  end

  -- Uznaj kalibrację za gotową gdy zakres > 5 dB i zebrano 20+ próbek
  if not calibrated and (maxSeen - minSeen) > 5 and sampleCount >= 20 then
    calibrated = true
  end

  -- ── Normalizacja 0–100 ────────────────────────────────────────────────────
  local range    = math.max(10, maxSeen - minSeen)
  local strength = clamp((avg - minSeen) * (100 / range), 0, 100)

  -- ── Percepcyjne mapowanie (większa czułość daleko od celu) ───────────────
  local perceptual = math.sqrt(strength / 100) * 100

  -- ── Kadencja beepów ───────────────────────────────────────────────────────
  local period = clamp(120 - perceptual, 8, 120)
  if now - lastBeep >= period then
    local freq = 500 + (perceptual * 7)                     -- 500–1200 Hz
    local dur  = clamp(10 + perceptual * 0.2, 10, 40)       -- 10–40 ms
    playTone(freq, dur, 0, 0)
    lastBeep = now
  end

  -- ── UI ───────────────────────────────────────────────────────────────────
  lcd.clear()
  lcd.drawText(2, 2, "ELRS Finder+", MIDSIZE)
  lcd.drawText(2, 18, string.format("Src:%s", kind), 0)
  lcd.drawText(60, 18, string.format("Raw:%d", raw), 0)

  lcd.drawText(2, 30, "Strength:", 0)
  lcd.drawRectangle(58, 30, 66, 10)
  if calibrated then
    local bar = math.floor(strength * 64 / 100)
    lcd.drawFilledRectangle(59, 31, bar, 8, 0)
  else
    lcd.drawText(60, 30, "cal...", 0)
  end

  lcd.drawText(2, 44, string.format("Avg:%d", math.floor(avg)), 0)
  lcd.drawText(2, 54, string.format("Range:%d..%d", minSeen, maxSeen), 0)

  return 0
end

return { run = run_func }
