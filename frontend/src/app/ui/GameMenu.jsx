import { useState, useEffect, useRef } from "react";
import PixelButton from "./PixelButton";
import PlayerSelect from "./PlayerSelect";
import MetaheadTitle from "./MetaheadTitle";
import ChestRedeemModal from "./ChestRedeemModal";
import LevelProgressBar from "./LevelProgressBar";
import CoinDisplay from "./CoinDisplay";
import { playerUrls } from "../lib/playerUrls";
import { socketService } from "@/services/socketService";

const GameBackGround = "/GameBackGround.png";

const GameMenu = ({ onSelectMode, onMarketplace }) => {
  let ownedImages = [0, 1] ;
  const [selectedPlayer, setSelectedPlayer] = useState(0);
  const [showChestModal, setShowChestModal] = useState(false);
  const [playerCreated, setPlayerCreated] = useState(false);
  const [isMatchmaking, setIsMatchmaking] = useState(false);
  const [roomJoined, setRoomJoined] = useState(false);
  const [playersInRoom, setPlayersInRoom] = useState(0);
  const [waitingForPlayers, setWaitingForPlayers] = useState(false);
  const [bothPlayersReady, setBothPlayersReady] = useState(false);
  const readyPlayersRef = useRef(new Set());

  // Store onSelectMode in a ref to avoid dependency issues
  const onSelectModeRef = useRef(onSelectMode);
  onSelectModeRef.current = onSelectMode;




    // Event handlers
    const handlePlayerCreated = (data) => {
      console.log("Player created in GameMenu:", data);
      setPlayerCreated(true);
    };

    const handleRoomJoined = (data) => {
      console.log("Room joined in GameMenu:", data);
      setRoomJoined(true);
      // Use players array length from backend data
      const currentPlayers = data.players ? data.players.length : 1;
      setPlayersInRoom(currentPlayers);
      setWaitingForPlayers(currentPlayers < 2);
      setIsMatchmaking(false);

      // Store room data for position assignment
      if (typeof window !== "undefined") {
        window.__HEADBALL_ROOM_DATA = data;
        console.log("Stored room data for position assignment:", data);

        // Store socket ID globally for reliable access
        const socketId = socketService.getSocket()?.id;
        window.__HEADBALL_SOCKET_ID = socketId;
        console.log("Stored socket ID for position assignment:", socketId);

        // Determine player position based on join order - more reliable approach
        let playerPosition = null;

        if (data.players && Array.isArray(data.players) && socketId) {
          // Find our player index in the players array
          const playerIndex = data.players.findIndex(
            (player) =>
              player.socketId === socketId ||
              player.id === socketId ||
              player.playerId === socketId
          );

          if (playerIndex !== -1) {
            // First player (index 0) = player1, Second player (index 1) = player2
            playerPosition = playerIndex === 0 ? "player1" : "player2";
            console.log(
              `Player found at index ${playerIndex}, assigned position: ${playerPosition}`
            );
          } else {
            // Fallback: if we can't find the player, assume we're the latest to join
            playerPosition = currentPlayers === 1 ? "player1" : "player2";
            console.log(
              `Player not found in array, using player count fallback: ${playerPosition}`
            );
          }
        } else {
          // Fallback: use player count
          playerPosition = currentPlayers === 1 ? "player1" : "player2";
          console.log(
            `Using simple player count assignment: ${playerPosition}`
          );
        }

        window.__HEADBALL_PLAYER_POSITION = playerPosition;
        console.log("Final player position assigned:", playerPosition);
      }

      // If this player joins a room that already has 2 players, auto-start the game
      if (currentPlayers >= 2) {
        console.log(
          "Joined room with 2 players, starting game automatically..."
        );
        setWaitingForPlayers(false);
        // Auto-start the game after a short delay (only if not already starting)
        if (!bothPlayersReady) {
          setBothPlayersReady(true);
          setTimeout(() => {
            setRoomJoined(false);
            setWaitingForPlayers(false);
            setBothPlayersReady(false);
            onSelectModeRef.current("online");
          }, 2000); // 2 second delay to show "loading game" message
        }
      }
    };

    const handlePlayerJoinedRoom = (data) => {
      console.log("Player joined room in GameMenu:", data);
      // Use players array length from backend data
      const currentPlayers = data.players
        ? data.players.length
        : socketService.getPlayersInRoom();
      setPlayersInRoom(currentPlayers);

      // Update stored room data
      if (typeof window !== "undefined") {
        window.__HEADBALL_ROOM_DATA = data;
        console.log("Updated room data:", data);

        // Store socket ID globally for reliable access
        const socketId = socketService.getSocket()?.id;
        window.__HEADBALL_SOCKET_ID = socketId;
        console.log("Updated socket ID for position assignment:", socketId);

        // Only reassign position if we don't already have one set correctly
        const existingPosition = window.__HEADBALL_PLAYER_POSITION;

        if (!existingPosition) {
          console.log("No existing position found, assigning new position...");

          // Update player position using the same reliable logic
          let playerPosition = null;

          if (data.players && Array.isArray(data.players) && socketId) {
            // Find our player index in the players array
            const playerIndex = data.players.findIndex(
              (player) =>
                player.socketId === socketId ||
                player.id === socketId ||
                player.playerId === socketId
            );

            if (playerIndex !== -1) {
              // First player (index 0) = player1, Second player (index 1) = player2
              playerPosition = playerIndex === 0 ? "player1" : "player2";
              console.log(
                `Player found at index ${playerIndex}, assigned position: ${playerPosition}`
              );
            } else {
              // Fallback: if we can't find the player, assume we're the latest to join
              playerPosition = currentPlayers === 1 ? "player1" : "player2";
              console.log(
                `Player not found in array, using player count fallback: ${playerPosition}`
              );
            }
          } else {
            // Fallback: use player count
            playerPosition = currentPlayers === 1 ? "player1" : "player2";
            console.log(
              `Using simple player count assignment: ${playerPosition}`
            );
          }

          window.__HEADBALL_PLAYER_POSITION = playerPosition;
          console.log("New player position assigned:", playerPosition);
        } else {
          console.log(`Keeping existing position: ${existingPosition}`);
        }
      }

      // If we have 2 players, start the game automatically
      if (currentPlayers >= 2) {
        console.log("Two players in room, starting game automatically...");
        setWaitingForPlayers(false);
        // Auto-start the game after a short delay (only if not already starting)
        if (!bothPlayersReady) {
          setBothPlayersReady(true);
          setTimeout(() => {
            setRoomJoined(false);
            setWaitingForPlayers(false);
            setBothPlayersReady(false);
            onSelectModeRef.current("online");
          }, 2000); // 2 second delay to show "loading game" message
        }
      }
    };

    const handlePlayerReady = (data) => {
      console.log("Player ready in GameMenu:", data);

      // Check if this is the local player or remote player
      const socketId = socketService.getSocket()?.id;
      const playerId = data.socketId || data.playerId;

      if (playerId === socketId) {
        // Local player is ready
        readyPlayersRef.current.add(playerId);
        console.log("Local player marked as ready");
      } else {
        // Remote player is ready
        readyPlayersRef.current.add(playerId);
        console.log("Remote player marked as ready");
      }

      // Check if both players are ready
      // Use the data from the server if available, otherwise check our tracking
      if (data.allPlayersReady || readyPlayersRef.current.size >= 2) {
        setBothPlayersReady(true);
        console.log("Both players are ready, starting game...");

        // Start the game after a short delay
        setTimeout(() => {
          setRoomJoined(false);
          setWaitingForPlayers(false);
          onSelectModeRef.current("online"); // This will trigger the loading screen
        }, 1000);
      }
    };

    // Register event listeners
    socketService.on("player-created", handlePlayerCreated);
    socketService.on("room-joined", handleRoomJoined);
    socketService.on("player-joined-room", handlePlayerJoinedRoom);
    socketService.on("player-ready", handlePlayerReady);



  useEffect(() => {
    function onError(data) {
      if (
        data.type === "GAME_ERROR" &&
        data.message === "Player already in a room"
      ) {
        // Reset and retry
        socketService.forceReconnect().then(() => {
          // You may want to pass player info here if needed
          socketService.findMatch({ selectedPlayer });
        });
      }
    }
    socketService.on("error", onError);
    return () => socketService.off("error", onError);
  }, [selectedPlayer]);

  useEffect(() => {
    function onRoomJoined(data) {
      setGameLoading(false); // Hide the loading overlay
      // Reset ready state when joining a new room
      setBothPlayersReady(false);
      readyPlayersRef.current.clear();
    }
    socketService.on("room-joined", onRoomJoined);
    return () => socketService.off("room-joined", onRoomJoined);
  }, []);

  useEffect(() => {
    function onLeftRoom(data) {
      // Reset ready state when leaving room
      setBothPlayersReady(false);
      readyPlayersRef.current.clear();
    }
    socketService.on("left-room", onLeftRoom);
    return () => socketService.off("left-room", onLeftRoom);
  }, []);

  const handlePlayerChange = (direction) => {
    if (!ownedImages.length) return;
    setSelectedPlayer((prev) =>
      direction === "next"
        ? (prev + 1) % ownedImages.length
        : (prev - 1 + ownedImages.length) % ownedImages.length
    );
  };

  const handleOnlineClick = () => {
    // Prevent multiple clicks
    if (isMatchmaking || roomJoined) {
      console.log("Matchmaking already in progress, ignoring click");
      return;
    }

    // Reset ready state for new match
    setBothPlayersReady(false);
    readyPlayersRef.current.clear();

    if (socketService.isSocketConnected() && playerCreated) {
      console.log("Starting matchmaking...");
      setIsMatchmaking(true);
      socketService.findMatch({
        playerId: socketService.getSocket()?.id,
        selectedPlayer: selectedPlayer,
      });
    } else {
      console.error(
        "Cannot start matchmaking: socket not connected or player not created"
      );
    }
  };

  const handleCancelMatchmaking = () => {
    setIsMatchmaking(false);
    socketService.cancelMatchmaking();
  };

  return (
    <div
      style={{
        height: "100vh",
        position: "relative",
        backgroundImage: `url(${GameBackGround})`,
        backgroundSize: "cover",
        backgroundPosition: "center bottom",
        backgroundRepeat: "no-repeat",
        imageRendering: "pixelated",
        overflow: "hidden",
      }}
    >
      <div className="flex items-center justify-between px-4 py-2">
        <div className="flex items-center">
          <div className={`"hidden"`}>
          </div>
          <div
            className={`${
              "flex items-center font-pixel"
            }`}
          >
          </div>
        </div>
        <div className="flex items-center gap-4">
          <div className={`"block"`}>
          </div>
        </div>
      </div>

      {/* Title overlay */}
      <div
        style={{
          position: "absolute",
          top: 32,
          left: "50%",
          transform: "translateX(-50%)",
          zIndex: 10,
          pointerEvents: "none",
        }}
      >
        <MetaheadTitle />
      </div>
      {/* Player Selector - Positioned on the left */}
      <div
        style={{
          position: "absolute",
          left: 32,
          top: "50%",
          transform: "translateY(-50%)",
          zIndex: 10,
        }}
      >
        {/* Level and Coin UI */}
        <div className={`"block"} mb-4`}>
          <div style={{ marginBottom: 12 }}>
            <LevelProgressBar level={1} xp={0} />
            <CoinDisplay />
          </div>
          <PlayerSelect
            ownedImages={ownedImages}
            selectedIdx={selectedPlayer}
            onPlayerChange={handlePlayerChange}
          />
          {/* Redeem Chests Section */}
          <div style={{ marginTop: 32, width: "100%" }}>
            <PixelButton
              variant="menu"
              size="large"
              onClick={() => setShowChestModal(true)}
              style={{
                display: "flex",
                flexDirection: "row",
                alignItems: "center",
                justifyContent: "flex-start",
              }}
            >
              <img
                src="/chest.png"
                alt="Chest"
                style={{ height: 56, marginRight: 24, marginLeft: 8 }}
              />
              <span
                style={{
                  display: "flex",
                  flexDirection: "column",
                  alignItems: "flex-start",
                  lineHeight: 1,
                }}
              >
                <span style={{ fontSize: "1.1em", fontWeight: "bold" }}>
                  REDEEM
                </span>
                <span style={{ fontSize: "1.1em", fontWeight: "bold" }}>
                  CHESTS
                </span>
              </span>
            </PixelButton>
          </div>
        </div>
      </div>
      {/* Game Buttons - Positioned on the right */}
      <div
        style={{
          position: "absolute",
          right: 32,
          top: "50%",
          transform: "translateY(-50%)",
          zIndex: 10,
          width: 320,
          display: "flex",
          flexDirection: "column",
          gap: 16,
        }}
      >
        <div
          className={`${
            playerCreated && !isMatchmaking && !roomJoined
              ? "block"
              : "hidden"
          } mb-4`}
        >
          <PixelButton
            variant="menu"
            size="hald-custom"
            style={{ fontSize: 25, padding: "30px 55px" }}
            onClick={handleOnlineClick}
            disabled={isMatchmaking || roomJoined}
          >
            <span className="flex flex-col items-center w-full leading-tight">
              <span>ENTER GAME</span>
              <span className="text-xs mt-0.5" style={{ fontWeight: 400 }}>
                ONLINE 1VS1
              </span>
            </span>
          </PixelButton>
        </div>

        {/* Show waiting message when authenticated but player not created yet */}
        <div
          className={`${
            !playerCreated
              ? "block"
              : "hidden"
          } mb-4`}
        >
          <div className="pixel-card rounded-none p-4 text-center bg-blue-900 border-2 border-yellow-400">
            <span className="text-white font-mono text-sm">
              Connecting to game server...
            </span>
          </div>
        </div>
        <div className="button-row-custom">
          <PixelButton
            variant="menu"
            size="half-custom"
            onClick={() => onSelectModeRef.current("2player")}
          >
            OFFLINE
          </PixelButton>
          <PixelButton
            variant="menu"
            size="half-custom"
            onClick={() => onSelectModeRef.current("vsAI")}
          >
            1 VS AI
          </PixelButton>
        </div>
        <PixelButton
          variant="menu"
          size="large"
          style={{ fontSize: 25, padding: "30px 55px" }}
          onClick={onMarketplace}
        >
          MARKETPLACE
        </PixelButton>
      </div>
      {showChestModal && (
        <ChestRedeemModal onClose={() => setShowChestModal(false)} />
      )}
      {/* Matchmaking Modal */}
      {(isMatchmaking ||
        roomJoined ||
        waitingForPlayers ||
        bothPlayersReady) && (
        <div
          style={{
            position: "fixed",
            inset: 0,
            background: "rgba(0,0,0,0.9)",
            zIndex: 10000,
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
          }}
        >
          <div
            style={{
              background: "#1e293b",
              border: "4px solid #ffd600",
              borderRadius: "8px",
              padding: "32px",
              textAlign: "center",
              maxWidth: "500px",
              width: "90%",
            }}
          >
            <h2
              style={{
                color: "#fde047",
                fontFamily: '"Press Start 2P", monospace',
                fontSize: "24px",
                marginBottom: "20px",
                textShadow: "2px 2px 0 #000",
              }}
            >
              {isMatchmaking && "FINDING MATCH..."}
              {roomJoined &&
                !waitingForPlayers &&
                playersInRoom < 2 &&
                "ROOM JOINED!"}
              {roomJoined &&
                playersInRoom >= 2 &&
                !bothPlayersReady &&
                "LOADING GAME..."}
              {waitingForPlayers && "WAITING FOR PLAYERS"}
              {bothPlayersReady && "STARTING GAME..."}
            </h2>

            <div
              style={{
                color: "#fff",
                fontFamily: '"Press Start 2P", monospace',
                fontSize: "16px",
                marginBottom: "20px",
                lineHeight: "1.5",
              }}
            >
              {isMatchmaking && (
                <>
                  <div style={{ marginBottom: "10px" }}>
                    🔍 Searching for opponents...
                  </div>
                  <div style={{ fontSize: "12px", color: "#94a3b8" }}>
                    Please wait while we find a match
                  </div>
                </>
              )}

              {roomJoined && (
                <>
                  <div style={{ marginBottom: "10px" }}>
                    🎮 Players in room: {playersInRoom}/2
                  </div>
                  {waitingForPlayers && playersInRoom < 2 && (
                    <div style={{ fontSize: "12px", color: "#94a3b8" }}>
                      Waiting for another player to join...
                    </div>
                  )}
                  {playersInRoom >= 2 && !bothPlayersReady && (
                    <>
                      <div
                        style={{
                          fontSize: "12px",
                          color: "#10b981",
                          marginBottom: "10px",
                        }}
                      >
                        Both players joined! Loading game...
                      </div>
                    </>
                  )}
                  {bothPlayersReady && (
                    <div style={{ fontSize: "12px", color: "#10b981" }}>
                      Both players ready! Starting game...
                    </div>
                  )}
                </>
              )}
            </div>

            {/* Loading animation - only show during matchmaking or when both players are ready */}
            {(isMatchmaking || bothPlayersReady) && (
              <div
                style={{
                  display: "flex",
                  justifyContent: "center",
                  marginBottom: "20px",
                }}
              >
                <div
                  style={{
                    width: "40px",
                    height: "40px",
                    border: "4px solid #374151",
                    borderTop: "4px solid #fde047",
                    borderRadius: "50%",
                    animation: "spin 1s linear infinite",
                  }}
                />
              </div>
            )}

            {/* Cancel button - only show during matchmaking */}
            {isMatchmaking && (
              <PixelButton
                variant="menu"
                size="large"
                onClick={handleCancelMatchmaking}
                style={{
                  backgroundColor: "#dc2626",
                  borderColor: "#991b1b",
                }}
              >
                CANCEL
              </PixelButton>
            )}
          </div>
        </div>
      )}
      {/* CSS for loading animation */}
      <style jsx>{`
        @keyframes spin {
          0% {
            transform: rotate(0deg);
          }
          100% {
            transform: rotate(360deg);
          }
        }
      `}</style>
    </div>
  );
};

export default GameMenu;
