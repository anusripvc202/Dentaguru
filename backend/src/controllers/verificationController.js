const { Dentist, Clinic, User, Notification } = require('../models/Schemas');
const { supabaseAdmin } = require('../config/supabase');

// 1. ADMIN: GET DENTISTS FOR VERIFICATION
exports.getDentistsForVerification = async (req, res) => {
    try {
        const { status } = req.query;
        let query = supabaseAdmin.from('dentists').select('*, users(name, email, phone), clinics(clinic_name, location)');
        if (status) {
            query = query.eq('verification_status', status);
        }
        const { data, error } = await query.order('created_at', { ascending: false });
        if (error) {
            const fallback = await Dentist.find();
            return res.json({ success: true, count: fallback.length, dentists: fallback });
        }
        res.json({ success: true, count: data.length, dentists: data });
    } catch (err) {
        console.error('Get Dentists Verification Error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to fetch dentists for verification.' });
    }
};

// 2. ADMIN: VERIFY / APPROVE / REJECT / SUSPEND DENTIST
exports.verifyDentist = async (req, res) => {
    const { id } = req.params;
    const { status, notes } = req.body; // 'VERIFIED', 'REJECTED', 'SUSPENDED'
    try {
        const validStatuses = ['VERIFIED', 'REJECTED', 'SUSPENDED', 'PENDING_VERIFICATION'];
        if (!validStatuses.includes(status)) {
            return res.status(400).json({ success: false, message: 'Invalid verification status.' });
        }

        const { data, error } = await supabaseAdmin
            .from('dentists')
            .update({ verification_status: status, updated_at: new Date().toISOString() })
            .eq('id', id)
            .select()
            .single();

        if (error) throw error;

        // Create Notification for Dentist
        if (data && data.user_id) {
            await Notification.create({
                recipient_role: 'Dentist',
                recipient_id: data.user_id,
                title: `Account Verification Update`,
                message: `Your dentist verification status is now set to: ${status}. ${notes || ''}`,
                type: 'verification'
            });
        }

        res.json({
            success: true,
            message: `Dentist verification status updated to ${status}.`,
            dentist: data
        });
    } catch (err) {
        console.error('Verify Dentist Error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to update dentist verification status.' });
    }
};

// 3. ADMIN: GET CLINICS FOR VERIFICATION
exports.getClinicsForVerification = async (req, res) => {
    try {
        const { status } = req.query;
        let query = supabaseAdmin.from('clinics').select('*');
        if (status) {
            query = query.eq('verification_status', status);
        }
        const { data, error } = await query.order('created_at', { ascending: false });
        if (error) {
            const fallback = await Clinic.find();
            return res.json({ success: true, count: fallback.length, clinics: fallback });
        }
        res.json({ success: true, count: data.length, clinics: data });
    } catch (err) {
        console.error('Get Clinics Verification Error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to fetch clinics for verification.' });
    }
};

// 4. ADMIN: VERIFY / APPROVE / REJECT / SUSPEND CLINIC
exports.verifyClinic = async (req, res) => {
    const { id } = req.params;
    const { status, notes } = req.body; // 'VERIFIED', 'REJECTED', 'SUSPENDED'
    try {
        const validStatuses = ['VERIFIED', 'REJECTED', 'SUSPENDED', 'PENDING_VERIFICATION'];
        if (!validStatuses.includes(status)) {
            return res.status(400).json({ success: false, message: 'Invalid verification status.' });
        }

        const isVerifiedBool = status === 'VERIFIED';

        const { data, error } = await supabaseAdmin
            .from('clinics')
            .update({
                verification_status: status,
                verified: isVerifiedBool,
                updated_at: new Date().toISOString()
            })
            .eq('id', id)
            .select()
            .single();

        if (error) throw error;

        res.json({
            success: true,
            message: `Clinic verification status updated to ${status}.`,
            clinic: data
        });
    } catch (err) {
        console.error('Verify Clinic Error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to update clinic verification status.' });
    }
};
