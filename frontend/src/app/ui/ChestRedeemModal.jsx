import React, { useState } from "react";
const commonChestImg = "/common-chest.png";
const rareChestImg = "/rare-chest.png";
const legendaryChestImg = "/legendary-chest.png";

const chestTypes = [
  { label: "Common", cost: 10, img: commonChestImg },
  { label: "Rare", cost: 50, img: rareChestImg },
  { label: "Legendary", cost: 100, img: legendaryChestImg },
];

const ChestRedeemModal = ({ onClose }) => {
  let data = [1, 2, 3];
  const [buyingBoxType, setBuyingBoxType] = useState(null); // Track which box is being bought
  const [openingBoxType, setOpeningBoxType] = useState(null); // Track which box is being opened
  const [currentStep, setCurrentStep] = useState(""); // Track current step

  // Function to handle opening a box
  const handleOpenBox = async (boxType) => {
    // Check if user has boxes to open
    if (!data || !data[boxType] || data[boxType] === 0) {
      alert("You don't have any boxes of this type to open!");
      return;
    }

    try {
      setOpeningBoxType(boxType);
      // Simulate opening box
      setTimeout(() => {
        alert("Box opened successfully!");
        setOpeningBoxType(null);
      }, 2000);
    } catch (error) {
      console.error("Error opening box:", error);
      alert("Failed to open box. Please try again.");
      setOpeningBoxType(null);
    }
  };

  // Function to handle the full buy process
  const handleBuyBox = async (boxType) => {
    try {
      setBuyingBoxType(boxType);

      setCurrentStep("Processing purchase...");

      // Simulate buying box
      setTimeout(() => {
        alert("Box purchased successfully!");
        setBuyingBoxType(null);
        setCurrentStep("");
      }, 2000);
    } catch (error) {
      console.error("Error in buy process:", error);
      alert("Failed to complete purchase. Please try again.");
      setBuyingBoxType(null);
      setCurrentStep("");
    }
  };

  // Check if a specific box type is being bought
  const isBoxBeingBought = (boxType) => {
    return buyingBoxType === boxType;
  };

  // Check if a specific box type is being opened
  const isBoxBeingOpened = (boxType) => {
    return openingBoxType === boxType;
  };

  return (
    <div
      style={{
        position: "fixed",
        top: 0,
        left: 0,
        width: "100vw",
        height: "100vh",
        background: "rgba(0,0,0,0.5)",
        zIndex: 1000,
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
      }}
    >
      <div
        style={{
          width: "66vw",
          maxWidth: 700,
          minHeight: 400,
          background: "#ffe066",
          border: "6px solid #e0b800",
          borderRadius: 12,
          boxShadow: "0 0 24px #0008",
          position: "relative",
          display: "flex",
          flexDirection: "column",
          alignItems: "center",
          padding: 32,
        }}
      >
        <button
          onClick={onClose}
          style={{
            position: "absolute",
            top: 16,
            right: 24,
            background: "none",
            border: "none",
            fontSize: 32,
            fontWeight: "bold",
            color: "#333",
            cursor: "pointer",
            zIndex: 10,
          }}
          aria-label="Close"
        >
          ×
        </button>
        <h2
          style={{
            fontFamily: "inherit",
            fontSize: 32,
            marginBottom: 24,
            letterSpacing: 2,
            textShadow: "2px 2px #fff",
          }}
        >
          REDEEM CHESTS
        </h2>

        <div
          style={{
            display: "flex",
            gap: 40,
            justifyContent: "center",
            width: "100%",
          }}
        >
          {chestTypes.map((chest, i) => (
            <div
              key={chest.label}
              style={{
                display: "flex",
                flexDirection: "column",
                alignItems: "center",
                minWidth: 140,
              }}
            >
              <div style={{ position: "relative", marginBottom: 8 }}>
                <img
                  src={chest.img}
                  alt={chest.label}
                  style={{ width: 100, height: 100 }}
                />
                <span
                  style={{
                    position: "absolute",
                    bottom: 6,
                    right: 10,
                    background: "#222",
                    color: "#ffe066",
                    fontWeight: "bold",
                    fontFamily: "monospace",
                    fontSize: 18,
                    borderRadius: 8,
                    padding: "2px 10px",
                    border: "2px solid #e0b800",
                    boxShadow: "1px 1px #bfa000",
                  }}
                >
                  x {data ? data[i]?.toString() : null}
                </span>
              </div>
              <div
                style={{ fontWeight: "bold", fontSize: 20, marginBottom: 8 }}
              >
                {chest.label}
              </div>
              <div
                style={{
                  display: "flex",
                  flexDirection: "column",
                  gap: 8,
                  width: "100%",
                }}
              >
                <button
                  onClick={() => handleBuyBox(i)}
                  disabled={isBoxBeingBought(i)}
                  style={{
                    background: isBoxBeingBought(i) ? "#ccc" : "#ffe066",
                    border: "3px solid #e0b800",
                    borderRadius: 6,
                    fontFamily: "inherit",
                    fontWeight: "bold",
                    fontSize: 16,
                    padding: "12px 18px",
                    cursor: isBoxBeingBought(i) ? "not-allowed" : "pointer",
                    boxShadow: "2px 2px #bfa000",
                    opacity: isBoxBeingBought(i) ? 0.6 : 1,
                    minHeight: "48px",
                  }}
                >
                  {isBoxBeingBought(i)
                    ? currentStep || "PROCESSING..."
                    : `BUY (${chest.cost} COINS)`}
                </button>
                <button
                  onClick={() => handleOpenBox(i)}
                  disabled={
                    isBoxBeingOpened(i) ||
                    !data ||
                    !data[i] ||
                    data[i] === 0
                  }
                  style={{
                    background: isBoxBeingOpened(i) ? "#ccc" : "#fff",
                    border: "3px solid #e0b800",
                    borderRadius: 6,
                    fontFamily: "inherit",
                    fontWeight: "bold",
                    fontSize: 18,
                    padding: "12px 18px",
                    cursor:
                      isBoxBeingOpened(i) ||
                      !data ||
                      !data[i] ||
                      data[i] === 0
                        ? "not-allowed"
                        : "pointer",
                    boxShadow: "2px 2px #bfa000",
                    opacity:
                      isBoxBeingOpened(i) ||
                      !data ||
                      !data[i] ||
                      data[i] === 0
                        ? 0.6
                        : 1,
                  }}
                >
                  {isBoxBeingOpened(i) ? "OPENING..." : "OPEN"}
                </button>
              </div>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
};

export default ChestRedeemModal;
