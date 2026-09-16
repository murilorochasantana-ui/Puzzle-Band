import Sparkline from './Sparkline';

export default function StatTile({ label, value, unit, color, history }) {
  return (
    <div className="stat-tile">
      <div className="stat-tile__top">
        <span className="stat-tile__label">{label}</span>
        <Sparkline values={history} color={color} />
      </div>
      <div className="stat-tile__value">
        {value}
        <span className="stat-tile__unit">{unit}</span>
      </div>
    </div>
  );
}
