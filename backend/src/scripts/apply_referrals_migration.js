require('dotenv').config({ path: require('path').resolve(__dirname, '../../.env') });
const { Client } = require('pg');

async function runMigration() {
  const connectionString = process.env.DATABASE_URL || process.env.POSTGRES_URI;
  console.log('Connecting to PostgreSQL database at:', connectionString ? connectionString.replace(/:[^:@]+@/, ':****@') : 'UNDEFINED');
  
  if (!connectionString) {
    console.error('❌ DATABASE_URL or POSTGRES_URI is not set in backend/.env');
    process.exit(1);
  }

  const client = new Client({
    connectionString,
    ssl: { rejectUnauthorized: false }
  });

  try {
    await client.connect();
    console.log('✅ Connected to Supabase PostgreSQL database.');

    const sql = `
      -- 1. Create Referrals Table
      CREATE TABLE IF NOT EXISTS public.referrals (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          referrer_patient_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
          referred_patient_id UUID REFERENCES public.users(id) ON DELETE SET NULL,
          referred_patient_name VARCHAR(255),
          referred_patient_mobile VARCHAR(50),
          referred_patient_age VARCHAR(20),
          referred_patient_gender VARCHAR(50),
          referred_patient_city VARCHAR(100),
          referred_patient_pincode VARCHAR(20),
          referred_patient_location VARCHAR(255),
          required_specialist VARCHAR(255),
          clinical_complaint TEXT,
          doctor_id UUID REFERENCES public.dentists(id) ON DELETE SET NULL,
          status VARCHAR(50) DEFAULT 'Pending',
          rejection_reason TEXT,
          whatsapp_status VARCHAR(50) DEFAULT 'Pending',
          referral_date TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
          referrer_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
          referred_user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
          referral_code VARCHAR(100),
          appointment_id UUID REFERENCES public.appointments(id) ON DELETE SET NULL,
          assigned_doctor_id UUID REFERENCES public.dentists(id) ON DELETE SET NULL,
          created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
          updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
      );

      -- 2. Add any missing columns
      ALTER TABLE public.referrals ADD COLUMN IF NOT EXISTS referrer_patient_id UUID REFERENCES public.users(id) ON DELETE CASCADE;
      ALTER TABLE public.referrals ADD COLUMN IF NOT EXISTS referred_patient_id UUID REFERENCES public.users(id) ON DELETE SET NULL;
      ALTER TABLE public.referrals ADD COLUMN IF NOT EXISTS referred_patient_name VARCHAR(255);
      ALTER TABLE public.referrals ADD COLUMN IF NOT EXISTS referred_patient_mobile VARCHAR(50);
      ALTER TABLE public.referrals ADD COLUMN IF NOT EXISTS referred_patient_age VARCHAR(20);
      ALTER TABLE public.referrals ADD COLUMN IF NOT EXISTS referred_patient_gender VARCHAR(50);
      ALTER TABLE public.referrals ADD COLUMN IF NOT EXISTS referred_patient_city VARCHAR(100);
      ALTER TABLE public.referrals ADD COLUMN IF NOT EXISTS referred_patient_pincode VARCHAR(20);
      ALTER TABLE public.referrals ADD COLUMN IF NOT EXISTS referred_patient_location VARCHAR(255);
      ALTER TABLE public.referrals ADD COLUMN IF NOT EXISTS required_specialist VARCHAR(255);
      ALTER TABLE public.referrals ADD COLUMN IF NOT EXISTS clinical_complaint TEXT;
      ALTER TABLE public.referrals ADD COLUMN IF NOT EXISTS doctor_id UUID REFERENCES public.dentists(id) ON DELETE SET NULL;
      ALTER TABLE public.referrals ADD COLUMN IF NOT EXISTS status VARCHAR(50) DEFAULT 'Pending';
      ALTER TABLE public.referrals ADD COLUMN IF NOT EXISTS rejection_reason TEXT;
      ALTER TABLE public.referrals ADD COLUMN IF NOT EXISTS whatsapp_status VARCHAR(50) DEFAULT 'Pending';
      ALTER TABLE public.referrals ADD COLUMN IF NOT EXISTS referral_date TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP;

      -- 3. Create Indexes
      CREATE INDEX IF NOT EXISTS idx_referrals_referrer_patient_id ON public.referrals(referrer_patient_id);
      CREATE INDEX IF NOT EXISTS idx_referrals_referred_patient_id ON public.referrals(referred_patient_id);
      CREATE INDEX IF NOT EXISTS idx_referrals_referred_patient_mobile ON public.referrals(referred_patient_mobile);
      CREATE INDEX IF NOT EXISTS idx_referrals_doctor_id ON public.referrals(doctor_id);
      CREATE INDEX IF NOT EXISTS idx_referrals_status ON public.referrals(status);

      -- 4. Enable RLS and Grant Permissions
      ALTER TABLE public.referrals ENABLE ROW LEVEL SECURITY;

      DO $$ 
      BEGIN
          IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'referrals' AND policyname = 'Allow All Referrals') THEN
              CREATE POLICY "Allow All Referrals" ON public.referrals FOR ALL USING (true) WITH CHECK (true);
          END IF;
      END $$;

      -- 5. Grant access to anon and authenticated roles
      GRANT ALL ON public.referrals TO anon;
      GRANT ALL ON public.referrals TO authenticated;
      GRANT ALL ON public.referrals TO service_role;

      -- 6. Reload PostgREST schema cache
      NOTIFY pgrst, 'reload schema';
      NOTIFY pgrst, 'reload config';
    `;

    console.log('🚀 Executing SQL migration...');
    await client.query(sql);
    console.log('🎉 Migration successfully executed and PostgREST schema reloaded!');

    // Verify table exists
    const checkRes = await client.query(`
      SELECT column_name, data_type 
      FROM information_schema.columns 
      WHERE table_schema = 'public' AND table_name = 'referrals'
    `);
    console.log(`📋 Found ${checkRes.rows.length} columns in public.referrals table:`);
    checkRes.rows.forEach(r => console.log(`   - ${r.column_name} (${r.data_type})`));

  } catch (err) {
    console.error('❌ Error executing migration:', err);
  } finally {
    await client.end();
  }
}

runMigration();
