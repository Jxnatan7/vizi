import React from 'react';

interface HeaderProps {
  bookCount: number;
}

export const Header: React.FC<HeaderProps> = ({ bookCount }) => {
  return (
    <header className="top-bar">
      <div>
        <h1 className="app-title">BookAI</h1>
        <p className="app-subtitle">Detecção em tempo real</p>
      </div>
      <div className={`count-badge ${bookCount > 0 ? 'active' : ''}`}>
        <span className="count-number">{bookCount}</span>
        <span className="count-label">Livros</span>
      </div>
    </header>
  );
};