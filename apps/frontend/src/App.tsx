function App() {
    const apiBase = import.meta.env.VITE_API_BASE_URL || 'http://localhost:8765';

    return (
        <div style={{ fontFamily: 'system-ui, sans-serif', padding: '2rem', color: '#e0e0e0', background: '#111', minHeight: '100vh' }}>
            <h1 style={{ fontSize: '1.5rem', marginBottom: '0.5rem' }}>Amb-Iskarna</h1>
            <p style={{ opacity: 0.6 }}>Backend target: <code>{apiBase}</code></p>
            <p style={{ opacity: 0.4, marginTop: '1rem' }}>Dashboard coming soon — Milestone 2</p>
        </div>
    );
}

export default App;
