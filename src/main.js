import { Simulation } from './Simulation.js';
import { Renderer } from './renderer/Renderer.js';

const CANVAS_W = 900;
const CANVAS_H = 680;

function initCanvas() {
  const canvas = document.getElementById('bit-market-canvas');
  canvas.width = CANVAS_W;
  canvas.height = CANVAS_H;
  return canvas;
}

function main() {
  const canvas = initCanvas();
  const simulation = new Simulation(CANVAS_W, CANVAS_H);
  const renderer = new Renderer(canvas);

  function loop() {
    simulation.update();
    renderer.render(simulation);
    requestAnimationFrame(loop);
  }

  requestAnimationFrame(loop);
}

main();
