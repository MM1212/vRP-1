
local PlayerState = class("PlayerState", vRP.Extension)

-- STATIC

PlayerState.weapon_types = {
  "WEAPON_KNIFE",
  "WEAPON_STUNGUN",
  "WEAPON_FLASHLIGHT",
  "WEAPON_NIGHTSTICK",
  "WEAPON_HAMMER",
  "WEAPON_BAT",
  "WEAPON_GOLFCLUB",
  "WEAPON_CROWBAR",
  "WEAPON_PISTOL",
  "WEAPON_COMBATPISTOL",
  "WEAPON_APPISTOL",
  "WEAPON_PISTOL50",
  "WEAPON_MICROSMG",
  "WEAPON_SMG",
  "WEAPON_ASSAULTSMG",
  "WEAPON_ASSAULTRIFLE",
  "WEAPON_CARBINERIFLE",
  "WEAPON_ADVANCEDRIFLE",
  "WEAPON_MG",
  "WEAPON_COMBATMG",
  "WEAPON_PUMPSHOTGUN",
  "WEAPON_SAWNOFFSHOTGUN",
  "WEAPON_ASSAULTSHOTGUN",
  "WEAPON_BULLPUPSHOTGUN",
  "WEAPON_STUNGUN",
  "WEAPON_SNIPERRIFLE",
  "WEAPON_HEAVYSNIPER",
  "WEAPON_REMOTESNIPER",
  "WEAPON_GRENADELAUNCHER",
  "WEAPON_GRENADELAUNCHER_SMOKE",
  "WEAPON_RPG",
  "WEAPON_PASSENGER_ROCKET",
  "WEAPON_AIRSTRIKE_ROCKET",
  "WEAPON_STINGER",
  "WEAPON_MINIGUN",
  "WEAPON_GRENADE",
  "WEAPON_STICKYBOMB",
  "WEAPON_SMOKEGRENADE",
  "WEAPON_BZGAS",
  "WEAPON_MOLOTOV",
  "WEAPON_FIREEXTINGUISHER",
  "WEAPON_PETROLCAN",
  "WEAPON_DIGISCANNER",
  "WEAPON_BRIEFCASE",
  "WEAPON_BRIEFCASE_02",
  "WEAPON_BALL",
  "WEAPON_FLARE"
}

-- METHODS

function PlayerState:__construct()
  vRP.Extension.__construct(self)

  self.state_ready = false
  self.save_interval = 30

  -- update task
  Citizen.CreateThread(function()
    while true do
      Citizen.Wait(self.save_interval*1000)

      if self.state_ready then
        local x,y,z = vRP.EXT.Base:getPosition()

        self.remote._update({
          position = {x=x,y=y,z=z},
          weapons = self:getWeapons(),
          customization = self:getCustomization(),
          health = self:getHealth(),
          armour = self:getArmour()
        })
      end
    end
  end)
end

-- WEAPONS

function PlayerState:getWeapons()
  local player = GetPlayerPed(-1)

  local ammo_types = {} -- remember ammo type to not duplicate ammo amount

  local weapons = {}
  for k,v in pairs(PlayerState.weapon_types) do
    local hash = GetHashKey(v)
    if HasPedGotWeapon(player,hash) then
      local weapon = {}
      weapons[v] = weapon

      local atype = Citizen.InvokeNative(0x7FEAD38B326B9F74, player, hash)
      if ammo_types[atype] == nil then
        ammo_types[atype] = true
        weapon.ammo = GetAmmoInPedWeapon(player,hash)
      else
        weapon.ammo = 0
      end
    end
  end

  return weapons
end

-- replace weapons (combination of getWeapons and giveWeapons)
-- return previous weapons
function PlayerState:replaceWeapons(weapons)
  local old_weapons = self:getWeapons()
  self:giveWeapons(weapons, true)
  return old_weapons
end

function PlayerState:giveWeapons(weapons, clear_before)
  local player = GetPlayerPed(-1)

  -- give weapons to player

  if clear_before then
    RemoveAllPedWeapons(player,true)
  end

  for k,weapon in pairs(weapons) do
    local hash = GetHashKey(k)
    local ammo = weapon.ammo or 0

    GiveWeaponToPed(player, hash, ammo, false)
  end
end

-- set player armour (0-100)
function PlayerState:setArmour(amount)
  SetPedArmour(GetPlayerPed(-1), amount)
end

function PlayerState:getArmour()
  return GetPedArmour(GetPlayerPed(-1))
end

function PlayerState:setHealth(amount)
  SetEntityHealth(GetPlayerPed(-1), math.floor(amount))
end

function PlayerState:getHealth()
  return GetEntityHealth(GetPlayerPed(-1))
end

--[[
function tvRP.dropWeapon()
  SetPedDropsWeapon(GetPlayerPed(-1))
end
--]]

-- PLAYER CUSTOMIZATION

-- parse part key (a ped part or a prop part)
-- return is_proppart, index
local function parse_part(key)
  if type(key) == "string" and string.sub(key,1,1) == "p" then
    return true,tonumber(string.sub(key,2))
  else
    return false,tonumber(key)
  end
end

function PlayerState:getDrawables(part)
  local isprop, index = parse_part(part)
  if isprop then
    return GetNumberOfPedPropDrawableVariations(GetPlayerPed(-1),index)
  else
    return GetNumberOfPedDrawableVariations(GetPlayerPed(-1),index)
  end
end

function PlayerState:getDrawableTextures(part,drawable)
  local isprop, index = parse_part(part)
  if isprop then
    return GetNumberOfPedPropTextureVariations(GetPlayerPed(-1),index,drawable)
  else
    return GetNumberOfPedTextureVariations(GetPlayerPed(-1),index,drawable)
  end
end

function PlayerState:getCustomization()
  local ped = GetPlayerPed(-1)

  local custom = {}

  custom.modelhash = GetEntityModel(ped)

  -- ped parts
  for i=0,20 do -- index limit to 20
    custom[i] = {GetPedDrawableVariation(ped,i), GetPedTextureVariation(ped,i), GetPedPaletteVariation(ped,i)}
  end

  -- props
  for i=0,10 do -- index limit to 10
    custom["p"..i] = {GetPedPropIndex(ped,i), math.max(GetPedPropTextureIndex(ped,i),0)}
  end

  return custom
end

-- partial customization (only what is set is changed)
function PlayerState:setCustomization(custom) -- indexed [drawable,texture,palette] components or props (p0...) plus .modelhash or .model
  local r = async()

  Citizen.CreateThread(function() -- new thread
    if custom then
      local ped = GetPlayerPed(-1)
      local mhash = nil

      -- model
      if custom.modelhash then
        mhash = custom.modelhash
      elseif custom.model then
        mhash = GetHashKey(custom.model)
      end

      if mhash then
        local i = 0
        while not HasModelLoaded(mhash) and i < 10000 do
          RequestModel(mhash)
          Citizen.Wait(10)
        end

        if HasModelLoaded(mhash) then
          -- changing player model remove weapons, armour and health, so save it

          vRP:triggerEvent("playerModelSave")

          local weapons = self:getWeapons()
          local armour = self:getArmour()
          local health = self:getHealth()

          SetPlayerModel(PlayerId(), mhash)

          self:giveWeapons(weapons,true)
          self:setArmour(armour)
          self:setHealth(health)

          vRP:triggerEvent("playerModelRestore")

          SetModelAsNoLongerNeeded(mhash)
        end
      end

      ped = GetPlayerPed(-1)

      -- parts
      for k,v in pairs(custom) do
        if k ~= "model" and k ~= "modelhash" then
          local isprop, index = parse_part(k)
          if isprop then
            if v[1] < 0 then
              ClearPedProp(ped,index)
            else
              SetPedPropIndex(ped,index,v[1],v[2],v[3] or 2)
            end
          else
            SetPedComponentVariation(ped,index,v[1],v[2],v[3] or 2)
          end
        end
      end
    end

    r()
  end)

  return r:wait()
end

-- EVENT

PlayerState.event = {}

-- TUNNEL
PlayerState.tunnel = {}

function PlayerState.tunnel:setStateReady(state)
  self.state_ready = state
end

function PlayerState.tunnel:setSaveInterval(value)
  self.save_interval = value
end

PlayerState.tunnel.getWeapons = PlayerState.getWeapons
PlayerState.tunnel.replaceWeapons = PlayerState.replaceWeapons
PlayerState.tunnel.giveWeapons = PlayerState.giveWeapons
PlayerState.tunnel.setArmour = PlayerState.setArmour
PlayerState.tunnel.getArmour = PlayerState.getArmour
PlayerState.tunnel.setHealth = PlayerState.setHealth
PlayerState.tunnel.getHealth = PlayerState.getHealth
PlayerState.tunnel.getDrawables = PlayerState.getDrawables
PlayerState.tunnel.getDrawableTextures = PlayerState.getDrawableTextures
PlayerState.tunnel.getCustomization = PlayerState.getCustomization
PlayerState.tunnel.setCustomization = PlayerState.setCustomization

-- fix invisible players by resetting customization every minutes
--[[
Citizen.CreateThread(function()
  while true do
    Citizen.Wait(60000)
    if state_ready then
      local custom = tvRP.getCustomization()
      custom.model = nil
      custom.modelhash = nil
      tvRP.setCustomization(custom)
    end
  end
end)
--]]

vRP:registerExtension(PlayerState)
