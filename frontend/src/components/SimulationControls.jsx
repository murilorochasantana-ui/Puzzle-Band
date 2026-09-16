const SPEEDS = [1, 4, 16, 60];

export default function SimulationControls({
  isPlaying,
  onTogglePlay,
  speed,
  onChangeSpeed,
  progress,
  total,
  onScrub,
  onReset,
}) {
  return (
    <div className="sim-controls">
      <div className="sim-controls__row">
        <button className="sim-controls__play" onClick={onTogglePlay} type="button">
          {isPlaying ? '⏸ Pausar' : '▶ Reproduzir'}
        </button>

        <button className="sim-controls__reset" onClick={onReset} type="button">
          ⟲ Reiniciar
        </button>

        <div className="sim-controls__speed">
          <span>Velocidade</span>
          {SPEEDS.map((s) => (
            <button
              key={s}
              type="button"
              className={`sim-controls__speed-btn ${speed === s ? 'is-active' : ''}`}
              onClick={() => onChangeSpeed(s)}
            >
              {s}x
            </button>
          ))}
        </div>
      </div>

      <input
        className="sim-controls__scrub"
        type="range"
        min={0}
        max={Math.max(0, total - 1)}
        value={progress}
        onChange={(e) => onScrub(Number(e.target.value))}
      />
      <div className="sim-controls__caption">
        Simulação de dados sintéticos · registro {progress + 1} de {total}
      </div>
    </div>
  );
}
