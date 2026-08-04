const { supabase, supabaseAdmin } = require('../config/supabase');

/**
 * Service to handle file operations using Supabase Cloud Storage
 */
class SupabaseStorageService {
    constructor() {
        this.defaultBucket = 'dentaguru-storage';
    }

    /**
     * Upload a buffer or file to Supabase Storage
     * @param {Buffer} fileBuffer - Binary content of the file
     * @param {string} fileName - Destination path/name in bucket
     * @param {string} mimeType - Content type (e.g., 'image/png', 'application/pdf')
     * @param {string} bucket - Bucket name (defaults to 'dentaguru-storage')
     */
    async uploadFile(fileBuffer, fileName, mimeType, bucket = this.defaultBucket) {
        try {
            const { data, error } = await supabaseAdmin.storage
                .from(bucket)
                .upload(fileName, fileBuffer, {
                    contentType: mimeType,
                    upsert: true
                });

            if (error) throw error;

            // Get public or signed URL
            const publicUrlData = supabase.storage
                .from(bucket)
                .getPublicUrl(fileName);

            return {
                success: true,
                path: data.path,
                publicUrl: publicUrlData.data.publicUrl,
                bucket
            };
        } catch (err) {
            console.error('Supabase Storage Upload Error:', err.message);
            throw err;
        }
    }

    /**
     * Generate a temporary pre-signed URL for private files (e.g., dental X-Rays)
     * @param {string} filePath - Path of file in bucket
     * @param {number} expiresIn - Expiration in seconds (default: 3600 = 1 hour)
     * @param {string} bucket - Bucket name
     */
    async getSignedUrl(filePath, expiresIn = 3600, bucket = this.defaultBucket) {
        try {
            const { data, error } = await supabaseAdmin.storage
                .from(bucket)
                .createSignedUrl(filePath, expiresIn);

            if (error) throw error;

            return {
                success: true,
                signedUrl: data.signedUrl,
                expiresIn
            };
        } catch (err) {
            console.error('Supabase Signed URL Error:', err.message);
            throw err;
        }
    }

    /**
     * Delete a file from Supabase Storage
     * @param {string} filePath - Path of file to delete
     * @param {string} bucket - Bucket name
     */
    async deleteFile(filePath, bucket = this.defaultBucket) {
        try {
            const { data, error } = await supabaseAdmin.storage
                .from(bucket)
                .remove([filePath]);

            if (error) throw error;

            return { success: true, deleted: data };
        } catch (err) {
            console.error('Supabase Storage Delete Error:', err.message);
            throw err;
        }
    }
}

module.exports = new SupabaseStorageService();
