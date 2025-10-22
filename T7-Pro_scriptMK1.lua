local prevpulse, count, prev_minute = 0, 0, 0
LJ.IntervalConfig(0, 1000)
LJ.IntervalConfig(1, 10)

-- printed pinouts are different from internal and registers call in code checkout
-- https://support.labjack.com/docs/mux80-ain-expansion-board-datasheet 
-- https://support.labjack.com/docs/appendix-c-ain-registers
-- differential pins are exclusively paired, be sure that your Differential positive and negative pin are compatible

local AIN = {53, 50, 52, 51, 67, 66, 63, 62, 64}
local AIN_ADDR = {106, 100, 104, 102, 134, 132, 126, 124, 128}

local LW_upwelling_k1 =  9.093
local LW_upwelling_k2 =  1.016

local LW_downwelling_k1 = 8.542
local LW_downwelling_k2 = 1.021

local SW_downwelling_factor = 22.85
local SW_upwelling_factor = 29.86

local rtc, err = MB.RA(61510, 0, 6)
if err ~= 0 then MB.W(6000, 1, 0) return end
prev_minute = rtc[5]
local filename = string.format("RMBL_ENV_DATA_MK2")
print("Filename: " .. filename)

local function checkFileFlag()
  local flag = LJ.CheckFileFlag()
  if flag ~= 0 then LJ.ClearFileFlag() 
    end
end

local function writeval(f, v, last) f:write(string.format("%.3f%s", v, last and "\n" or ",")) end

local function ain(addr) return MB.R(addr, 3) end

local file = io.open(filename, "a")
if not file then MB.W(6000, 1, 0) return end
file:write("datetime,T_therm_dn,LWR_dn,T_therm_up,LWR_up,SWR_dn,SWR_up,snow_depth,wind_dir,wind_speed,Pressure,Humidity,H_temp,Inclinometer_X_angle, Inclinometer_Y_Angle\n")
file:close()


local snow_depth_initial = ain(AIN_ADDR[5])
print("Snow depth initial reference:", snow_depth_initial)


-- Main loop
while true do
  checkFileFlag()
  if LJ.CheckInterval(1) then
    local pulse = MB.R(2001, 0)
    if pulse > prevpulse then count = count + 1 end
    prevpulse = pulse

    rtc, err = MB.RA(61510, 0, 6)
    if err ~= 0 then MB.W(6000, 1, 0) return end

    if rtc[5] ~= prev_minute then
      prev_minute = rtc[5]
      file = io.open(filename, "a")
      if not file then MB.W(6000, 1, 0) return end
      file:write(string.format("%04d/%02d/%02d %02d:%02d:%02d,", rtc[1], rtc[2], rtc[3], rtc[4], rtc[5], rtc[6]))

      local ain64 = ((ain(AIN_ADDR[9])/10) * 100) - 40 -- H temp
      print("temperature: ", ain64)

      local ain70 = ain(140) -- Therm dn
      local DW_LW_Therm_Resistance = (24900* (ain70/(2.5-ain70)))
      local DW_LW_Internal_Temp

      if ain64 >= 0 then
        DW_LW_Internal_Temp = 1 / (.000932794 + (.000221451 * math.log(DW_LW_Therm_Resistance)) + .000000126233 * math.log(DW_LW_Therm_Resistance)^3)
      else 
        DW_LW_Internal_Temp = 1 / (.000932960 + (.000221424 * math.log(DW_LW_Therm_Resistance)) + .000000126329 * math.log(DW_LW_Therm_Resistance)^3)
      end
      
      Incoming_LW_mV = ain(100)
      Incoming_LW = (LW_upwelling_k1*Incoming_LW_mV*1000) + (LW_upwelling_k2*(5.6704*(10^-8))*(DW_LW_Internal_Temp^4))
      print("Incoming Longwave radiation:", Incoming_LW)

      local ain71 = ain(142) -- Therm dn
      local UW_LW_Therm_Resistance = (24900* (ain71/(2.5-ain71)))
      local UW_LW_Internal_Temp

      if ain64 >= 0 then
        UW_LW_Internal_Temp = 1 / (.000932794 + (.000221451 * math.log(UW_LW_Therm_Resistance)) + .000000126233 * math.log(UW_LW_Therm_Resistance)^3)
      else
        UW_LW_Internal_Temp = 1 / (.000932960 + (.000221424 * math.log(UW_LW_Therm_Resistance)) + .000000126329 * math.log(UW_LW_Therm_Resistance)^3)
      end
      local Outgoing_LW_mV = ain(106)
      local Outgoing_LW = (LW_downwelling_k1*Outgoing_LW_mV*1000) + (LW_downwelling_k2*(5.6704*(10^-8))*(UW_LW_Internal_Temp^4))
      print("Outgoing Longwave radiation:", Outgoing_LW)

      local Incoming_SW_mV = ain(104)
      local Incoming_SW = SW_downwelling_factor * Incoming_SW_mV * 1000
      print("Incoming Shortwave radiation", Incoming_SW)

      local Reflected_SW_mV = ain(102)
      local Reflected_SW = SW_upwelling_factor * Reflected_SW_mV * 1000
      print("Reflected Shortwave radiation", Reflected_SW)

      LJ.IntervalConfig(0, 200)
      
      -- Wait until 2 seconds have passed
      while not LJ.CheckInterval(0) do
        -- Nothing here; just wait
      end

      local ain67_raw = ain(AIN_ADDR[5]) 
      local snow_depth = (snow_depth_initial - ain67_raw)
      print("Raw height:", ain67_raw, "Snow depth:", snow_depth)

      local ain66 = (ain(AIN_ADDR[6]) / 5.105) * 360 -- Wind dir
      print("wind direction: ", ain66)

      local wind_speed = (count / 60) * 2.45 -- Wind speed
      count = 0
      print("Wind speed:", wind_speed)

      local ain63 = (ain(AIN_ADDR[7]) * 11) + 5 -- Pressure
      print("pressure", ain63)

      local ain62 = ((ain(AIN_ADDR[8])/10) * 100) -- Humidity
      print("Humidity", ain62)
      
      local ain48 = ain(96)
      local X_angle = ((ain48 - 2.5)/0.0333)
      print("Inclinometer X angle", X_angle)
      
      local ain49 = ain(98)
      local Y_angle = ((ain49- 2.5)/0.0333)
      print("Inclinometer Y angle", Y_angle)

      writeval(file, ain70, false) -- LW Thermister downwelling
      writeval(file, Incoming_LW, false) -- incoming LW radiation  
      writeval(file, ain71, false) -- LW Thermister upwelling
      writeval(file, Outgoing_LW, false) -- outgoing LW radiation
      writeval(file, Incoming_SW, false) -- incoming SW radiation 
      writeval(file, Reflected_SW, false) -- reflected shortwave 
      writeval(file, snow_depth, false) -- snow depth 
      writeval(file, ain66, false) -- wind Direction
      writeval(file, wind_speed, false) -- wind speed
      writeval(file, ain63, false) -- Humidity 
      writeval(file, ain62, false) -- pressure
      writeval(file, X_angle, false)
      writeval(file, Y_angle, true)
      
      file:flush()
      file:close()
    end
  end
end