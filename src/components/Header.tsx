import React from 'react';

interface HeaderProps {
  bookCount: number;
}

export const Header: React.FC<HeaderProps> = ({ bookCount }) => {
  return (
    <header className="header">
      <h1>Book Detector AI</h1>
      <div className="tag">Books detected: {bookCount}</div>
    </header>
  );
};