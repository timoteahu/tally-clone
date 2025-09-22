import { useEffect, useMemo, useState } from "react";
import Particles, { initParticlesEngine } from "@tsparticles/react";
import { type Container, type Engine, OutMode } from "@tsparticles/engine";
import { loadSlim } from "@tsparticles/slim";
import { memo } from "react";

function ParticleBackground() {
  const [init, setInit] = useState(false);

  useEffect(() => {
    initParticlesEngine(async (engine: Engine) => {
      await loadSlim(engine);
    }).then(() => {
      setInit(true);
    });
  }, []);

  const particlesLoaded = async (container?: Container) => {
    console.log("Particles container loaded", container);
  };

  const options = useMemo(
    () => ({
      background: {
        color: {
          value: "transparent"
        }
      },
      particles: {
        number: {
          value: 80,
          density: {
            enable: true,
            area: 800
          }
        },
        color: {
          value: "#ffffff"
        },
        shape: {
          type: "circle"
        },
        opacity: {
          value: 0.5
        },
        size: {
          value: { min: 1, max: 3 }
        },
        links: {
          enable: true,
          distance: 150,
          color: "#ffffff",
          opacity: 0.4,
          width: 1
        },
        move: {
          enable: true,
          speed: 2,
          random: false,
          straight: false,
          outModes: {
            default: OutMode.out
          }
        }
      },
      interactivity: {
        events: {
          onHover: {
            enable: true,
            mode: "grab"
          },
          onClick: {
            enable: true,
            mode: "push"
          }
        },
        modes: {
          grab: {
            distance: 140,
            links: {
              opacity: 1
            }
          },
          push: {
            quantity: 4
          }
        }
      },
      detectRetina: true
    }),
    []
  );

  if (!init) {
    return null;
  }

  return (
    <div className="absolute inset-0 -z-10">
      <Particles
        id="tsparticles"
        className="h-full w-full"
        particlesLoaded={particlesLoaded}
        options={options}
      />
    </div>
  );
}

export default memo(ParticleBackground); 