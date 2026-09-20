import { GYRO_ACTIONS } from '../model/simulate';

export default function ManualControls({
  bpmTarget,
  onChangeBpm,
  edaTarget,
  onChangeEda,
  gyroAction,
  onChangeGyroAction,
  hrvTarget,
  onChangeHrv,
  movimentoRepetitivo,
  onToggleMovimentoRepetitivo,
  luzTarget,
  onChangeLuz,
  ruidoTarget,
  onChangeRuido,
  idade,
  onChangeIdade,
  isRunning,
  onToggleRunning,
  onReset,
  speed,
  onChangeSpeed,
  bufferLength,
}) {
  return (
    <div className="manual-controls">
      <div className="manual-controls__row">
        <button className="sim-controls__play" onClick={onToggleRunning} type="button">
          {isRunning ? '⏸ Pausar simulação' : '▶ Iniciar simulação'}
        </button>
        <button className="sim-controls__reset" onClick={onReset} type="button">
          ⟲ Reiniciar buffer
        </button>
        <div className="sim-controls__speed">
          <span>Velocidade</span>
          {[1, 2, 4].map((s) => (
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
        <span className="manual-controls__buffer">
          {bufferLength < 31 ? `coletando amostras: ${bufferLength}/31s` : `histórico: ${bufferLength}s`}
        </span>
      </div>

      <div className="manual-controls__group-label">Sensores fisiológicos</div>
      <div className="manual-controls__grid">
        <label className="manual-controls__field">
          <span>Batimento cardíaco: <strong>{bpmTarget} bpm</strong></span>
          <input
            className="manual-controls__bpm-range"
            type="range"
            min={50}
            max={190}
            value={bpmTarget}
            onChange={(e) => onChangeBpm(Number(e.target.value))}
          />
        </label>

        <label className="manual-controls__field">
          <span>Suor / EDA: <strong>{edaTarget.toFixed(1)} µS</strong></span>
          <input
            className="manual-controls__eda-range"
            type="range"
            min={1}
            max={16}
            step={0.1}
            value={edaTarget}
            onChange={(e) => onChangeEda(Number(e.target.value))}
          />
        </label>

        <label className="manual-controls__field">
          <span>HRV (variabilidade cardíaca): <strong>{hrvTarget} ms</strong></span>
          <input
            className="manual-controls__hrv-range"
            type="range"
            min={10}
            max={90}
            value={hrvTarget}
            onChange={(e) => onChangeHrv(Number(e.target.value))}
          />
        </label>

        <label className="manual-controls__field">
          <span>Idade da criança: <strong>{idade} anos</strong></span>
          <input
            type="range"
            min={5}
            max={12}
            value={idade}
            onChange={(e) => onChangeIdade(Number(e.target.value))}
          />
        </label>
      </div>

      <div className="manual-controls__group-label">Movimento (giroscópio + acelerômetro)</div>
      <div className="manual-controls__gyro">
        <span className="manual-controls__gyro-label">Intensidade — ação da criança</span>
        <div className="manual-controls__gyro-options">
          {GYRO_ACTIONS.map((action) => (
            <button
              key={action.id}
              type="button"
              className={`manual-controls__gyro-btn ${gyroAction === action.id ? 'is-active' : ''}`}
              onClick={() => onChangeGyroAction(action.id)}
            >
              {action.label}
            </button>
          ))}
        </div>
      </div>
      <div className="manual-controls__toggle-row">
        <span className="manual-controls__gyro-label">Padrão do movimento</span>
        <button
          type="button"
          className={`manual-controls__toggle-btn ${!movimentoRepetitivo ? 'is-active' : ''}`}
          onClick={() => onToggleMovimentoRepetitivo(false)}
        >
          Livre / errático (ex.: correr)
        </button>
        <button
          type="button"
          className={`manual-controls__toggle-btn ${movimentoRepetitivo ? 'is-active' : ''}`}
          onClick={() => onToggleMovimentoRepetitivo(true)}
        >
          Repetitivo (estereotipia)
        </button>
      </div>

      <div className="manual-controls__group-label">Sensores ambientais</div>
      <div className="manual-controls__grid">
        <label className="manual-controls__field">
          <span>Luminosidade: <strong>{luzTarget} lux</strong></span>
          <input
            type="range"
            min={0}
            max={1000}
            step={10}
            value={luzTarget}
            onChange={(e) => onChangeLuz(Number(e.target.value))}
          />
        </label>

        <label className="manual-controls__field">
          <span>Ruído ambiente: <strong>{ruidoTarget} dB</strong></span>
          <input
            type="range"
            min={20}
            max={100}
            value={ruidoTarget}
            onChange={(e) => onChangeRuido(Number(e.target.value))}
          />
        </label>
      </div>
    </div>
  );
}
