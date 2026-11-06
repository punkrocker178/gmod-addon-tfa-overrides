-- nZombies Chronicles balance for TFA weapons.
-- Add a class to NZTFABalance to override it. Pierce is the total number of zombies
-- one bullet may hit, counting the zombie the bullet already struck.
-- Only classes listed here are changed.

NZTFABalance = {
	iw3_barrett = {
		Damage = 220,
		Pierce = 5,
	},
	iw3_m40a3 = {
		Damage = 160,
		Pierce = 2,
	},
	iw3_r700 = {
		Damage = 100,
		Pierce = 2,
	},
	iw3_dragunov = {
		Damage = 120,
		Pierce = 2,
	},
	iw3_m21 = {
		Damage = 100,
		Pierce = 1,
	},
}

local PIERCE_REACH = 4096

local function IsInNzombiesChronicles()
	return engine.ActiveGamemode() == "nzombies_chronicles"
end

local function SetStat(wep, key, value)
	wep.Primary = wep.Primary or {}
	local field = string.match(key, "^Primary%.(.+)$")
	if field then
		wep.Primary[field] = value
	end
	if wep.SetStatRawL then
		wep:SetStatRawL(key, value)
	end
end

local function Apply(wep)
	if not IsInNzombiesChronicles() or not IsValid(wep) then return end
	local cfg = NZTFABalance[wep:GetClass()]
	if not cfg then return end

	if cfg.Damage then
		SetStat(wep, "Primary.Damage", cfg.Damage)
	end

	-- TFA's own penetration looks for an exit wound. nZombies nextbots usually
	-- do not provide one, and a successful exit would hit the same zombies again.
	if cfg.Pierce and cfg.Pierce > 1 then
		SetStat(wep, "Primary.PenetrationPower", 1)
		SetStat(wep, "Primary.MaxSurfacePenetrationCount", 0)
	end

	if wep.ClearStatCache then
		wep:ClearStatCache()
	end
end

local function WallBlocks(attacker, from, to)
	local tr = util.TraceLine({
		start = from,
		endpos = to,
		mask = MASK_SHOT,
		filter = function(ent)
			if ent == attacker then return false end
			if ent.IsValidZombie and ent:IsValidZombie() then return false end
			return true
		end,
	})
	return tr.Hit and tr.Fraction < 0.98
end

local function Pierce(attacker, wep, tr, dmginfo, count)
	if not SERVER or count <= 1 then return end
	if not IsValid(attacker) or not attacker:IsPlayer() then return end
	if not tr.Hit or not IsValid(tr.Entity) then return end
	if not tr.Entity.IsValidZombie or not tr.Entity:IsValidZombie() then return end
	if wep.NZTFAPierceTime == CurTime() then return end
	wep.NZTFAPierceTime = CurTime()

	local dir = tr.Normal
	if not dir or dir:LengthSqr() < 0.001 then
		dir = tr.HitPos - tr.StartPos
	end
	dir:Normalize()

	local origin = tr.StartPos or attacker:GetShootPos()
	local firstDist = (tr.HitPos - origin):Dot(dir)
	local found = ents.FindAlongRay(origin, origin + dir * PIERCE_REACH, Vector(-8, -8, -8), Vector(8, 8, 8))
	local hits = {}

	for _, ent in ipairs(found) do
		if ent ~= tr.Entity and ent.IsValidZombie and ent:IsValidZombie() and ent:Health() > 0 then
			local along = (ent:WorldSpaceCenter() - origin):Dot(dir)
			if along > firstDist + 4 then
				hits[#hits + 1] = { ent = ent, dist = along }
			end
		end
	end

	table.sort(hits, function(a, b)
		return a.dist < b.dist
	end)

	local extra = math.min(count - 1, #hits)
	local damage = dmginfo:GetDamage()
	local inflictor = IsValid(wep) and wep or attacker

	for i = 1, extra do
		local ent = hits[i].ent
		if WallBlocks(attacker, origin, ent:WorldSpaceCenter()) then break end
		if IsValid(ent) and ent:Health() > 0 then
			local dmg = DamageInfo()
			dmg:SetAttacker(attacker)
			dmg:SetInflictor(inflictor)
			dmg:SetDamage(damage)
			dmg:SetDamageType(DMG_BULLET)
			dmg:SetDamagePosition(ent:WorldSpaceCenter())
			dmg:SetDamageForce(dir * 100)
			dmg:SetReportedPosition(attacker:GetShootPos())
			ent:TakeDamageInfo(dmg)
		end
	end
end

hook.Add("OnEntityCreated", "nz_tfa_balance", function(ent)
	timer.Simple(0, function()
		if IsValid(ent) and ent:IsWeapon() then
			Apply(ent)
		end
	end)
end)

hook.Add("WeaponEquip", "nz_tfa_balance", function(wep)
	timer.Simple(0, function()
		Apply(wep)
	end)
end)

hook.Add("PlayerSwitchWeapon", "nz_tfa_balance", function(_, _, new)
	Apply(new)
end)

hook.Add("EntityFireBullets", "nz_tfa_balance_pierce", function(ent, data)
	if not IsInNzombiesChronicles() or not IsValid(ent) or not ent:IsPlayer() then return end

	local wep = ent:GetActiveWeapon()
	if not IsValid(wep) then return end

	local cfg = NZTFABalance[wep:GetClass()]
	if not cfg or not cfg.Pierce or cfg.Pierce <= 1 then return end

	local old = data.Callback
	data.Callback = function(attacker, tr, dmginfo)
		if old then
			old(attacker, tr, dmginfo)
		end
		Pierce(attacker, wep, tr, dmginfo, cfg.Pierce)
	end

	return true
end)
