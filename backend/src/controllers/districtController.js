// =============================================================================
// GS HEALTH – DISTRICT MANAGEMENT CONTROLLER
// Module: Multiple District Management & Sub-Admin District Mappings
// =============================================================================

const { District, SubAdminDistrict, User } = require('../models/Schemas');
const { isCloudEnv } = require('../config/secrets');

// 1. GET ALL ACTIVE DISTRICTS (Public & Authenticated)
exports.getDistricts = async (req, res) => {
    try {
        const { state, search } = req.query;
        const districts = await District.find({ is_active: true, state, search });
        res.json({
            success: true,
            count: districts.length,
            districts
        });
    } catch (err) {
        console.error('Get Districts Error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to retrieve districts.' });
    }
};

// 2. GET ALL DISTRICTS WITH STATS (Main Admin)
exports.getAdminDistricts = async (req, res) => {
    try {
        const districts = await District.find({});
        const result = [];

        for (const dist of districts) {
            const subAdminIds = await SubAdminDistrict.getSubAdminsForDistrict(dist.id);
            // Count active sub-admins
            let activeSubAdminCount = 0;
            for (const sId of subAdminIds) {
                const u = await User.findById(sId);
                if (u && (u.status === 'ACTIVE' || !u.status)) activeSubAdminCount++;
            }

            result.push({
                ...dist,
                sub_admins_count: subAdminIds.length,
                active_sub_admins_count: activeSubAdminCount
            });
        }

        res.json({
            success: true,
            count: result.length,
            districts: result
        });
    } catch (err) {
        console.error('Get Admin Districts Error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to retrieve admin districts.' });
    }
};

// 3. CREATE NEW DISTRICT (Main Admin)
exports.createDistrict = async (req, res) => {
    try {
        const { name, state, country, is_active } = req.body;
        const normalizedName = (name || '').trim();
        if (!normalizedName) {
            return res.status(400).json({ success: false, message: 'District name is required.' });
        }

        const existing = await District.findOne({ name: normalizedName });
        if (existing) {
            return res.status(409).json({ success: false, message: `District '${normalizedName}' already exists.` });
        }

        const district = await District.create({
            name: normalizedName,
            state: (state || 'Telangana').trim(),
            country: (country || 'India').trim(),
            is_active: is_active !== undefined ? is_active : true
        });

        res.status(201).json({
            success: true,
            message: `District '${district.name}' created successfully.`,
            district
        });
    } catch (err) {
        console.error('Create District Error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to create district.' });
    }
};

// 4. UPDATE DISTRICT (Main Admin)
exports.updateDistrict = async (req, res) => {
    try {
        const { id } = req.params;
        const { name, state, country, is_active } = req.body;

        const target = await District.findById(id);
        if (!target) {
            return res.status(404).json({ success: false, message: 'District not found.' });
        }

        const updates = {};
        if (name !== undefined) updates.name = (name || '').trim();
        if (state !== undefined) updates.state = (state || '').trim();
        if (country !== undefined) updates.country = (country || '').trim();
        if (is_active !== undefined) updates.is_active = is_active;

        const updated = await District.findByIdAndUpdate(id, updates);
        res.json({
            success: true,
            message: 'District updated successfully.',
            district: updated
        });
    } catch (err) {
        console.error('Update District Error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to update district.' });
    }
};

// 5. TOGGLE DISTRICT STATUS (Main Admin)
exports.toggleDistrictStatus = async (req, res) => {
    try {
        const { id } = req.params;
        const { is_active } = req.body;

        const target = await District.findById(id);
        if (!target) {
            return res.status(404).json({ success: false, message: 'District not found.' });
        }

        const newStatus = is_active !== undefined ? is_active : !target.is_active;
        const updated = await District.findByIdAndUpdate(id, { is_active: newStatus });

        res.json({
            success: true,
            message: `District '${updated.name}' is now ${newStatus ? 'Active' : 'Inactive'}.`,
            district: updated
        });
    } catch (err) {
        console.error('Toggle District Status Error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to toggle district status.' });
    }
};

// 6. GET SUB-ADMIN'S ASSIGNED DISTRICTS
exports.getSubAdminDistricts = async (req, res) => {
    try {
        const { id } = req.params; // Sub-admin user ID
        if (req.user) {
            const roleLower = (req.user.role || '').toString().trim().toLowerCase();
            const isMainAdmin = roleLower === 'admin' || roleLower === 'primaryadmin' || roleLower === 'primary_admin' || roleLower === 'superadmin' || roleLower === 'super_admin';
            const isOwnerSubAdmin = String(req.user.id || '').trim() === String(id || '').trim();
            if (!isMainAdmin && !isOwnerSubAdmin) {
                return res.status(403).json({ success: false, message: 'Access Denied: You can only view your own assigned districts.' });
            }
        } else if (isCloudEnv() || (req.headers && !req.headers['x-user-id'] && !req.headers.authorization)) {
            return res.status(401).json({ success: false, message: 'Authentication required.' });
        }
        const districts = await SubAdminDistrict.getDistrictsForSubAdmin(id);
        res.json({
            success: true,
            count: districts.length,
            districts
        });
    } catch (err) {
        console.error('Get Sub-Admin Districts Error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to retrieve coordinator districts.' });
    }
};

// 7. ASSIGN MULTIPLE DISTRICTS TO SUB-ADMIN (Main Admin)
exports.assignSubAdminDistricts = async (req, res) => {
    try {
        const { id } = req.params; // Sub-admin user ID
        const { districtIds } = req.body;

        if (!Array.isArray(districtIds)) {
            return res.status(400).json({ success: false, message: 'districtIds must be an array of district IDs.' });
        }

        const targetUser = await User.findById(id);
        if (!targetUser) {
            return res.status(404).json({ success: false, message: 'Coordinator user not found.' });
        }

        const assignedBy = req.user ? req.user.id : null;
        const assignedDistricts = await SubAdminDistrict.assignDistrictsToSubAdmin(id, districtIds, assignedBy);

        res.json({
            success: true,
            message: `Assigned ${assignedDistricts.length} district(s) to ${targetUser.name}.`,
            districts: assignedDistricts
        });
    } catch (err) {
        console.error('Assign Sub-Admin Districts Error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to assign districts to coordinator.' });
    }
};

// 8. REMOVE DISTRICT FROM SUB-ADMIN (Main Admin)
exports.removeSubAdminDistrict = async (req, res) => {
    try {
        const { id, districtId } = req.params;
        const removed = await SubAdminDistrict.removeDistrictFromSubAdmin(id, districtId);
        if (!removed) {
            return res.status(404).json({ success: false, message: 'District mapping not found for this coordinator.' });
        }

        res.json({
            success: true,
            message: 'District removed successfully from Coordinator.'
        });
    } catch (err) {
        console.error('Remove Sub-Admin District Error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to remove district from coordinator.' });
    }
};
