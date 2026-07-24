export default function handler(request, response) {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

  if (!url || !anonKey) {
    return response.status(500).json({ error: 'Supabase environment variables are missing.' });
  }

  response.setHeader('Cache-Control', 'no-store');
  return response.status(200).json({ url, anonKey });
}
