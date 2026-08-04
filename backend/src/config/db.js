const { supabaseAdmin } = require('./supabase');

let isConnectedFlag = false;

const isConnected = () => isConnectedFlag;

const connectDB = async () => {
    try {
        // Query users table to verify Supabase PostgreSQL connection & schema
        const { data, error } = await supabaseAdmin.from('users').select('count', { count: 'exact', head: true });
        
        if (error) {
            if (error.code === 'PGRST205' || error.message.includes('public.users')) {
                console.log('⚠️ Supabase PostgreSQL connected! (Run supabase_schema.sql in Supabase Dashboard SQL Editor to create tables)');
                isConnectedFlag = true;
                return;
            }
            throw error;
        }

        console.log('✅ Supabase PostgreSQL Database Connected & Schema Verified!');
        isConnectedFlag = true;
    } catch (err) {
        console.error('⚠️ Supabase Database Warning:', err.message);
        isConnectedFlag = false;
    }
};

module.exports = {
    connectDB,
    isConnected
};
