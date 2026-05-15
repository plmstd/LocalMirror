import React from "react";

const Button = ({ children, className }) => {
  return (
    <button
      className={`bg-primary hover:bg-text text-white px-6 py-2 rounded-md text-sm font-bold ${className}`}
    >
      {children}
    </button>
  );
};

export default Button;
