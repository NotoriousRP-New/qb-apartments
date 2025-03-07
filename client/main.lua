local QBCore = exports['qb-core']:GetCoreObject()
local ox_inventory = exports.ox_inventory

local InApartment = false
local ClosestHouse = nil
local CurrentApartment = nil
local IsOwned = false
local CurrentDoorBell = 0
local CurrentOffset = 0
local HouseObj = {}
local POIOffsets = nil
local RangDoorbell = nil

-- target variables
local InApartmentTargets = {}

-- polyzone variables
local IsInsideStashZone = false
local IsInsideExitPos= false
local IsInsideOutfitsZone = false
local IsInsideLogoutZone = false
local IsInsideEntPos = false

-- polyzone integration

local function ShowEntranceHeaderMenu()
    local headerMenu = {}

    if IsOwned then
        headerMenu[#headerMenu+1] = {
            title = Lang:t('text.enter'),
            event = 'apartments:client:EnterApartment',
        }
     elseif not IsOwned then
        headerMenu[#headerMenu+1] = {
            title = Lang:t('text.move_here'),
            event = 'apartments:client:UpdateApartment',
        }
     end

    headerMenu[#headerMenu+1] = {
        title = Lang:t('text.ring_doorbell'),
        event = 'apartments:client:DoorbellMenu',
    }

    lib.registerContext({
        id = 'apartment_context_menu',
        title = Lang:t('text.menu_header'),
        options = headerMenu
    })
    lib.showContext('apartment_context_menu')
end

local function ShowExitHeaderMenu()
    lib.registerContext({
        id = 'apartment_exit_context_menu',
        title = Lang:t('text.menu_header'),
        options = {
            { title = Lang:t('text.open_door'), event = 'apartments:client:OpenDoor', },
            { title = Lang:t('text.leave'), event = 'apartments:client:LeaveApartment', },
        }
    })
    lib.showContext('apartment_exit_context_menu')
end

local function RegisterApartmentEntranceZone(apartmentID, apartmentData)
    local coords = apartmentData.coords['enter']
    local boxName = 'apartmentEntrance_' .. apartmentID
    local boxData = apartmentData.polyzoneBoxData

    if boxData.created then
        return
    end

    local zone = BoxZone:Create(coords, boxData.length, boxData.width, {
        name = boxName,
        heading = 340.0,
        minZ = coords.z - 1.0,
        maxZ = coords.z + 5.0,
        debugPoly = false
    })

    zone:onPlayerInOut(function (isPointInside)
        if isPointInside and not InApartment then
            lib.showTextUI("[E] Use Apartment", {position = "left-center"})
            IsInsideEntPos = true
        else
            IsInsideEntPos = false
            lib.hideTextUI()
            CloseMenuFull()
        end
    end)

    boxData.created = true
    boxData.zone = zone
end

local function RegisterInApartmentZone(targetKey, coords, heading, text)
    if not InApartment then
        return
    end

    if InApartmentTargets[targetKey] and InApartmentTargets[targetKey].created then
        return
    end

    Wait(1500)

    local boxName = 'inApartmentTarget_' .. targetKey

    local zone = BoxZone:Create(coords, 1.5, 1.5, {
        name = boxName,
        heading = heading,
        minZ = coords.z - 1.0,
        maxZ = coords.z + 5.0,
        debugPoly = false
    })

    zone:onPlayerInOut(function (isPointInside)
        if isPointInside and text then
            if targetKey == "entrancePos" then
                lib.showTextUI("[E] Manage Apartment", {position = "left-center"})
            else
                lib.showTextUI(text, {position = "left-center"})
            end
        else
            lib.hideTextUI()
        end

        if targetKey == "entrancePos" then
            IsInsideExitPos = isPointInside
        end

        if targetKey == "stashPos" then
            IsInsideStashZone = isPointInside
        end

        if targetKey == "outfitsPos" then
            IsInsideOutfitsZone = isPointInside
        end

        if targetKey == "logoutPos" then
            IsInsideLogoutZone = isPointInside
        end

    end)

    InApartmentTargets[targetKey] = InApartmentTargets[targetKey] or {}
    InApartmentTargets[targetKey].created = true
    InApartmentTargets[targetKey].zone = zone
end


-- shared

local function SetApartmentsEntranceTargets()
    if Apartments.Locations and next(Apartments.Locations) then
        for id, apartment in pairs(Apartments.Locations) do
            if apartment and apartment.coords and apartment.coords['enter'] then
                RegisterApartmentEntranceZone(id, apartment)
            end
        end
    end
end

local function SetInApartmentTargets()
    if not POIOffsets then
        -- do nothing
        return
    end

    local entrancePos = vector3(Apartments.Locations[ClosestHouse].coords.enter.x - POIOffsets.exit.x, Apartments.Locations[ClosestHouse].coords.enter.y - POIOffsets.exit.y - 0.5, Apartments.Locations[ClosestHouse].coords.enter.z - CurrentOffset + POIOffsets.exit.z)
    local stashPos = vector3(Apartments.Locations[ClosestHouse].coords.enter.x - POIOffsets.stash.x, Apartments.Locations[ClosestHouse].coords.enter.y - POIOffsets.stash.y, Apartments.Locations[ClosestHouse].coords.enter.z - CurrentOffset + POIOffsets.stash.z)
    local outfitsPos = vector3(Apartments.Locations[ClosestHouse].coords.enter.x - POIOffsets.clothes.x, Apartments.Locations[ClosestHouse].coords.enter.y - POIOffsets.clothes.y, Apartments.Locations[ClosestHouse].coords.enter.z - CurrentOffset + POIOffsets.clothes.z)
    -- local logoutPos = vector3(Apartments.Locations[ClosestHouse].coords.enter.x - POIOffsets.logout.x, Apartments.Locations[ClosestHouse].coords.enter.y + POIOffsets.logout.y, Apartments.Locations[ClosestHouse].coords.enter.z - CurrentOffset + POIOffsets.logout.z)

    RegisterInApartmentZone('stashPos', stashPos, 0, "[E] " .. Lang:t('text.open_stash'))
    RegisterInApartmentZone('outfitsPos', outfitsPos, 0, "[E] " .. Lang:t('text.change_outfit'))
    -- RegisterInApartmentZone('logoutPos', logoutPos, 0, "[E] " .. Lang:t('text.logout'))
    RegisterInApartmentZone('entrancePos', entrancePos, 0, Lang:t('text.options'))
end

local function DeleteApartmentsEntranceTargets()
    if Apartments.Locations and next(Apartments.Locations) then
        for _, apartment in pairs(Apartments.Locations) do
            if apartment.polyzoneBoxData.zone then
                apartment.polyzoneBoxData.zone:destroy()
                apartment.polyzoneBoxData.zone = nil
            end
            apartment.polyzoneBoxData.created = false
        end
    end
end

local function DeleteInApartmentTargets()
    IsInsideStashZone = false
    IsInsideOutfitsZone = false
    IsInsideLogoutZone = false
    IsInsideExitPos = false

    if InApartmentTargets and next(InApartmentTargets) then
        for _, apartmentTarget in pairs(InApartmentTargets) do
            if apartmentTarget.zone then
                apartmentTarget.zone:destroy()
                apartmentTarget.zone = nil
            end
        end
    end
    InApartmentTargets = {}
end


-- utility functions

local function loadAnimDict(dict)
    while (not HasAnimDictLoaded(dict)) do
        RequestAnimDict(dict)
        Wait(5)
    end
end

local function openHouseAnim()
    loadAnimDict("anim@heists@keycard@")
    TaskPlayAnim( PlayerPedId(), "anim@heists@keycard@", "exit", 5.0, 1.0, -1, 16, 0, 0, 0, 0 )
    Wait(400)
    ClearPedTasks(PlayerPedId())
end

local function EnterApartment(house, apartmentId, new)
    TriggerServerEvent("InteractSound_SV:PlayOnSource", "houses_door_open", 0.1)
    openHouseAnim()
    Wait(250)
    QBCore.Functions.TriggerCallback('apartments:GetApartmentOffset', function(offset)
        if offset == nil or offset == 0 then
            QBCore.Functions.TriggerCallback('apartments:GetApartmentOffsetNewOffset', function(newoffset)
                if newoffset > 230 then
                    newoffset = 210
                end
                CurrentOffset = newoffset
                TriggerServerEvent("apartments:server:AddObject", apartmentId, house, CurrentOffset)
                local coords = { x = Apartments.Locations[house].coords.enter.x, y = Apartments.Locations[house].coords.enter.y, z = Apartments.Locations[house].coords.enter.z - CurrentOffset}
                local data = exports['qb-interior']:CreateApartmentFurnished(coords)
                Wait(100)
                HouseObj = data[1]
                POIOffsets = data[2]
                InApartment = true
                CurrentApartment = apartmentId
                ClosestHouse = house
                RangDoorbell = nil
                Wait(500)
                TriggerEvent('qb-weathersync:client:DisableSync')
                Wait(100)
                TriggerServerEvent('qb-apartments:server:SetInsideMeta', house, apartmentId, true, false)
                TriggerServerEvent("InteractSound_SV:PlayOnSource", "houses_door_close", 0.1)
                TriggerServerEvent("apartments:server:setCurrentApartment", CurrentApartment)

            end, house)
        else
            if offset > 230 then
                offset = 210
            end
            CurrentOffset = offset
            TriggerServerEvent("InteractSound_SV:PlayOnSource", "houses_door_open", 0.1)
            TriggerServerEvent("apartments:server:AddObject", apartmentId, house, CurrentOffset)
            local coords = { x = Apartments.Locations[ClosestHouse].coords.enter.x, y = Apartments.Locations[ClosestHouse].coords.enter.y, z = Apartments.Locations[ClosestHouse].coords.enter.z - CurrentOffset}
            local data = exports['qb-interior']:CreateApartmentFurnished(coords)
            Wait(100)
            HouseObj = data[1]
            POIOffsets = data[2]
            InApartment = true
            CurrentApartment = apartmentId
            Wait(500)
            TriggerEvent('qb-weathersync:client:DisableSync')
            Wait(100)
            TriggerServerEvent('qb-apartments:server:SetInsideMeta', house, apartmentId, true, true)
            TriggerServerEvent("InteractSound_SV:PlayOnSource", "houses_door_close", 0.1)
            TriggerServerEvent("apartments:server:setCurrentApartment", CurrentApartment)
        end

        if new then
            SetTimeout(1250, function()
                TriggerEvent('qb-clothes:client:CreateFirstCharacter')
            end)
        end
    end, apartmentId)
end

local function LeaveApartment(house)
    TriggerServerEvent("InteractSound_SV:PlayOnSource", "houses_door_open", 0.1)
    openHouseAnim()
    TriggerServerEvent("qb-apartments:returnBucket")
    DoScreenFadeOut(500)
    while not IsScreenFadedOut() do Wait(10) end
    exports['qb-interior']:DespawnInterior(HouseObj, function()
        TriggerEvent('qb-weathersync:client:EnableSync')
        SetEntityCoords(PlayerPedId(), Apartments.Locations[house].coords.enter.x, Apartments.Locations[house].coords.enter.y,Apartments.Locations[house].coords.enter.z)
        SetEntityHeading(PlayerPedId(), Apartments.Locations[house].coords.enter.w)
        Wait(1000)
        TriggerServerEvent("apartments:server:RemoveObject", CurrentApartment, house)
        TriggerServerEvent('qb-apartments:server:SetInsideMeta', CurrentApartment, false)
        CurrentApartment = nil
        InApartment = false
        CurrentOffset = 0
        DoScreenFadeIn(1000)
        TriggerServerEvent("InteractSound_SV:PlayOnSource", "houses_door_close", 0.1)
        TriggerServerEvent("apartments:server:setCurrentApartment", nil)

        DeleteInApartmentTargets()
        DeleteApartmentsEntranceTargets()
    end)
end

local function SetClosestApartment()
    local pos = GetEntityCoords(PlayerPedId())
    local current = nil
    local dist = 100
    for id, _ in pairs(Apartments.Locations) do
        local distcheck = #(pos - vector3(Apartments.Locations[id].coords.enter.x, Apartments.Locations[id].coords.enter.y, Apartments.Locations[id].coords.enter.z))
        if distcheck < dist then
            current = id
        end
    end
    if current ~= ClosestHouse and LocalPlayer.state.isLoggedIn and not InApartment then
        ClosestHouse = current
        QBCore.Functions.TriggerCallback('apartments:IsOwner', function(result)
            IsOwned = result
            DeleteApartmentsEntranceTargets()
            DeleteInApartmentTargets()
        end, ClosestHouse)
    end
end

function MenuOwners()
    QBCore.Functions.TriggerCallback('apartments:GetAvailableApartments', function(apartments)
        if next(apartments) == nil then
            QBCore.Functions.Notify(Lang:t('error.nobody_home'), "error", 3500)
            CloseMenuFull()
        else
            local aptsMenu = {}
            for k, v in pairs(apartments) do
                aptsMenu[#headerMenu+1] = {
                    title = v,
                    event = 'apartments:client:RingMenu',
                    args = { apartmentId = k }
                }
            end

            lib.registerContext({
                id = 'apartment_tennants_context_menu',
                title = Lang:t('text.tennants'),
                options = aptsMenu
            })
            lib.showContext('apartment_tennants_context_menu')
        end
    end, ClosestHouse)
end

function CloseMenuFull()
    lib.hideContext(false)
end


-- Event Handlers

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        if HouseObj ~= nil then
            exports['qb-interior']:DespawnInterior(HouseObj, function()
                CurrentApartment = nil
                TriggerEvent('qb-weathersync:client:EnableSync')
                DoScreenFadeIn(500)
                while not IsScreenFadedOut() do
                    Wait(10)
                end
                SetEntityCoords(PlayerPedId(), Apartments.Locations[ClosestHouse].coords.enter.x, Apartments.Locations[ClosestHouse].coords.enter.y,Apartments.Locations[ClosestHouse].coords.enter.z)
                SetEntityHeading(PlayerPedId(), Apartments.Locations[ClosestHouse].coords.enter.w)
                Wait(1000)
                InApartment = false
                DoScreenFadeIn(1000)
            end)
        end

        DeleteApartmentsEntranceTargets()
        DeleteInApartmentTargets()
    end
end)


-- Events

RegisterNetEvent('QBCore:Client:OnPlayerUnload', function()
    CurrentApartment = nil
    InApartment = false
    CurrentOffset = 0

    DeleteApartmentsEntranceTargets()
    DeleteInApartmentTargets()
end)

RegisterNetEvent('apartments:client:setupSpawnUI', function(cData)
    QBCore.Functions.TriggerCallback('apartments:GetOwnedApartment', function(result)
        if result then
            TriggerEvent('qb-spawn:client:setupSpawns', cData, false, nil)
            TriggerEvent('qb-spawn:client:openUI', true)
            TriggerEvent("apartments:client:SetHomeBlip", result.type)
        else
            if Apartments.Starting then
                TriggerEvent('qb-spawn:client:setupSpawns', cData, true, Apartments.Locations)
                TriggerEvent('qb-spawn:client:openUI', true)
            else
                TriggerEvent('qb-spawn:client:setupSpawns', cData, false, nil)
                TriggerEvent('qb-spawn:client:openUI', true)
            end
        end
    end, cData.citizenid)
end)

RegisterNetEvent('apartments:client:SpawnInApartment', function(apartmentId, apartment)
    local pos = GetEntityCoords(PlayerPedId())
    if RangDoorbell ~= nil then
        local doorbelldist = #(pos - vector3(Apartments.Locations[RangDoorbell].coords.enter.x, Apartments.Locations[RangDoorbell].coords.enter.y,Apartments.Locations[RangDoorbell].coords.enter.z))
        if doorbelldist > 5 then
            QBCore.Functions.Notify(Lang:t('error.to_far_from_door'))
            return
        end
    end
    ClosestHouse = apartment
    EnterApartment(apartment, apartmentId, true)
    IsOwned = true
end)

RegisterNetEvent('qb-apartments:client:LastLocationHouse', function(apartmentType, apartmentId)
    ClosestHouse = apartmentType
    EnterApartment(apartmentType, apartmentId, false)
end)

RegisterNetEvent('apartments:client:SetHomeBlip', function(home)
    CreateThread(function()
        SetClosestApartment()
        for name, _ in pairs(Apartments.Locations) do
            RemoveBlip(Apartments.Locations[name].blip)

            Apartments.Locations[name].blip = AddBlipForCoord(Apartments.Locations[name].coords.enter.x, Apartments.Locations[name].coords.enter.y, Apartments.Locations[name].coords.enter.z)
            if (name == home) then
                SetBlipSprite(Apartments.Locations[name].blip, 475)
            else
                SetBlipSprite(Apartments.Locations[name].blip, 476)
            end
            SetBlipDisplay(Apartments.Locations[name].blip, 4)
            SetBlipScale(Apartments.Locations[name].blip, 0.65)
            SetBlipAsShortRange(Apartments.Locations[name].blip, true)
            SetBlipColour(Apartments.Locations[name].blip, 3)

            BeginTextCommandSetBlipName("STRING")
            AddTextComponentSubstringPlayerName(Apartments.Locations[name].label)
            EndTextCommandSetBlipName(Apartments.Locations[name].blip)
        end
    end)
end)

RegisterNetEvent('apartments:client:RingMenu', function(data)
    RangDoorbell = ClosestHouse
    TriggerServerEvent("InteractSound_SV:PlayOnSource", "doorbell", 0.1)
    TriggerServerEvent("apartments:server:RingDoor", data.apartmentId, ClosestHouse)
end)

RegisterNetEvent('apartments:client:RingDoor', function(player, _)
    CurrentDoorBell = player
    TriggerServerEvent("InteractSound_SV:PlayOnSource", "doorbell", 0.1)
    QBCore.Functions.Notify(Lang:t('info.at_the_door'))
end)

RegisterNetEvent('apartments:client:DoorbellMenu', function()
    MenuOwners()
end)

RegisterNetEvent('apartments:client:EnterApartment', function()
    QBCore.Functions.TriggerCallback('apartments:GetOwnedApartment', function(result)
        if result ~= nil then
            EnterApartment(ClosestHouse, result.name)
        end
    end)
end)

RegisterNetEvent('apartments:client:UpdateApartment', function()
    local apartmentType = ClosestHouse
    local apartmentLabel = Apartments.Locations[ClosestHouse].label
    TriggerServerEvent("apartments:server:UpdateApartment", apartmentType, apartmentLabel)
    IsOwned = true

    DeleteApartmentsEntranceTargets()
    DeleteInApartmentTargets()
end)

RegisterNetEvent('apartments:client:OpenDoor', function()
    if CurrentDoorBell == 0 then
        QBCore.Functions.Notify(Lang:t('error.nobody_at_door'))
        return
    end
    TriggerServerEvent("apartments:server:OpenDoor", CurrentDoorBell, CurrentApartment, ClosestHouse)
    CurrentDoorBell = 0
end)

RegisterNetEvent('apartments:client:LeaveApartment', function()
    LeaveApartment(ClosestHouse)
end)

RegisterNetEvent('apartments:client:OpenStash', function()
    if CurrentApartment ~= nil then
        if ox_inventory:openInventory('stash', CurrentApartment) == false then
            TriggerServerEvent('apartments:server:loadstash', CurrentApartment)
            ox_inventory:openInventory('stash', CurrentApartment)
        end
        TriggerServerEvent("InteractSound_SV:PlayOnSource", "StashOpen", 0.4)
    end
end)

RegisterNetEvent('apartments:client:ChangeOutfit', function()
    TriggerServerEvent("InteractSound_SV:PlayOnSource", "Clothes1", 0.4)
    TriggerEvent('qb-clothing:client:openOutfitMenu')
end)

RegisterNetEvent('apartments:client:Logout', function()
    TriggerServerEvent('qb-houses:server:LogoutLocation')
end)


-- Threads

CreateThread(function ()
    local sleep = 5000
    while not LocalPlayer.state.isLoggedIn do
        -- do nothing
        Wait(sleep)
    end

    while true do
        sleep = 1000

        if IsInsideEntPos then
            sleep = 0
            if IsControlJustPressed(0, 38) then
                print("pressed")
                ShowEntranceHeaderMenu()
            end
        end

        if not InApartment and not IsInsideEntPos then
            SetClosestApartment()
            SetApartmentsEntranceTargets()
            sleep = 1000
        elseif InApartment then
            sleep = 0

            SetInApartmentTargets()

            if IsInsideStashZone then
                if IsControlJustPressed(0, 38) then
                    TriggerEvent('apartments:client:OpenStash')
                end
            end

            if IsInsideExitPos then
                if IsControlJustPressed(0, 38) then
                    ShowExitHeaderMenu()
                end
            end


            if IsInsideOutfitsZone then
                if IsControlJustPressed(0, 38) then
                    TriggerEvent('apartments:client:ChangeOutfit')
                end
            end

            if IsInsideLogoutZone then
                if IsControlJustPressed(0, 38) then
                    TriggerEvent('apartments:client:Logout')
                end
            end
        end

        Wait(sleep)
    end
end)
