import { useEffect, useMemo, useRef, useState } from 'react';
import './App.css';
import { CHILDREN, ACTIVITY_LABELS } from './data/children';
import StatTile from './components/StatTile';
import StressBadge from './components/StressBadge';
import BpmChart from './components/BpmChart';
import SimulationControls from './components/SimulationControls';
import AlertBanner from './components/AlertBanner';

const WINDOW_SIZE = 60; // seconds shown on the chart
const TICK_MS = 250; // base playback tick

function App() {
  const [childId, setChildId] = useState(CHILDREN[0].id);
  const child = useMemo(() => CHILDREN.find((c) => c.id === childId), [childId]);
  const readings = child.readings;

  const [cursor, setCursor] = useState(WINDOW_SIZE);
  const [isPlaying, setIsPlaying] = useState(true);
  const [speed, setSpeed] = useState(4);
  const intervalRef = useRef(null);

  useEffect(() => {
    setCursor(WINDOW_SIZE);
    setIsPlaying(true);
  }, [childId]);

  useEffect(() => {
    if (!isPlaying) return undefined;

    intervalRef.current = setInterval(() => {
      setCursor((c) => {
        const next = c + speed;
        return next >= readings.length ? WINDOW_SIZE : next;
      });
    }, TICK_MS);

    return () => clearInterval(intervalRef.current);
  }, [isPlaying, speed, readings.length]);

  const current = readings[Math.min(cursor, readings.length - 1)];
  const windowPoints = readings.slice(Math.max(0, cursor - WINDOW_SIZE), cursor);

  const bpmHistory = windowPoints.map((p) => p.bpm);
  const edaHistory = windowPoints.map((p) => p.eda_uS);
  const gyroHistory = windowPoints.map((p) => p.gyro_mag_dps);

  return (
    <div className="dashboard" data-theme="light">
      <header className="dashboard__header">
        <div>
          <h1>Puzzle Band</h1>
          <p className="dashboard__subtitle">
            Painel do cuidador · dados sintéticos em reprodução simulada
          </p>
        </div>

        <label className="child-select">
          <span>Criança</span>
          <select value={childId} onChange={(e) => setChildId(e.target.value)}>
            {CHILDREN.map((c) => (
              <option key={c.id} value={c.id}>
                {c.label} · {c.idade} anos
              </option>
            ))}
          </select>
        </label>
      </header>

      <AlertBanner level={current.nivel_estresse} childLabel={child.label} />

      <section className="dashboard__status">
        <StressBadge level={current.nivel_estresse} />
        <span className="dashboard__activity">
          Atividade atual: <strong>{ACTIVITY_LABELS[current.atividade] ?? current.atividade}</strong>
        </span>
        <span className="dashboard__timestamp">
          {new Date(current.timestamp).toLocaleString('pt-BR')}
        </span>
      </section>

      <section className="dashboard__tiles">
        <StatTile
          label="Frequência cardíaca"
          value={current.bpm}
          unit="bpm"
          color="var(--series-1)"
          history={bpmHistory}
        />
        <StatTile
          label="Atividade eletrodérmica (GSR)"
          value={current.eda_uS.toFixed(2)}
          unit="µS"
          color="var(--series-3)"
          history={edaHistory}
        />
        <StatTile
          label="Movimento (giroscópio)"
          value={current.gyro_mag_dps.toFixed(1)}
          unit="dps"
          color="var(--series-7)"
          history={gyroHistory}
        />
      </section>

      <section className="dashboard__chart-card">
        <h2>Frequência cardíaca — últimos {WINDOW_SIZE}s</h2>
        <BpmChart points={windowPoints} />
        <p className="dashboard__chart-note">
          Área sombreada indica trechos rotulados como episódio de estresse no dataset.
        </p>
      </section>

      <section className="dashboard__sim-card">
        <h2>Simulação de dados</h2>
        <SimulationControls
          isPlaying={isPlaying}
          onTogglePlay={() => setIsPlaying((p) => !p)}
          speed={speed}
          onChangeSpeed={setSpeed}
          progress={cursor}
          total={readings.length}
          onScrub={(v) => setCursor(Math.max(WINDOW_SIZE, v))}
          onReset={() => setCursor(WINDOW_SIZE)}
        />
      </section>
    </div>
  );
}

export default App;
