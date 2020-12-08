import java.util.Queue;
import java.util.ArrayDeque;

final byte T_NOTHING = 0;
final byte T_WIRE    = 1;
final byte T_CROSS   = 2;
final byte T_GATE    = 3;
final byte T_SWITCH  = 4;
final byte T_GATE_IN = 5;

int w, h;
final color tiles[] = {
  #000000, // nothing
  #752525, // wire
  #696a6a, // cross
  #ffffff, // gate
  #3f3f74, // switch
  #45283c, // gate input
};
final color active_tiles[] = {
  #FF00FF, // nothing
  #dc7070, // wire
  #FF00FF, // cross
  #fffba6, // gate
  #355cb1, // switch
  #a91b7d, // gate input
};

class Point {
  int x, y;
  Point(int _x, int _y) { x = _x; y = _y; }
}

byte[] grid; // msb = is_active
int cell_size = 8;
final int MAX_TILE_UPDATES = 1000;
Queue<Point> tile_updates[];
int flip = 0;
byte[] visited; // bitset? slower
int steps_per_sec = 1;
final int speeds[] = {1, 2, 4, 8, 16, 32, 64, 128, 256, 512, 1024, 2048};
int selected_speed = 6;
long last_draw_time;

int cam_x = 0, cam_y = 0;
int drag_x, drag_y;
boolean dragging = false;
boolean paused = true;

void reload_image() {
  PImage img = loadImage("circuit.png");
  w = img.width;
  h = img.height;
  grid = new byte[w * h];
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      byte t = lookup_tile(img.pixels[x + y * w]);
      if (t == -1) {
        // ignore other colors
        t = T_NOTHING;
      }
      grid[x + y * w] = t;
    }
  }
  
  visited = new byte[w * h];
  
  tile_updates = new ArrayDeque[2];
  tile_updates[0] = new ArrayDeque(MAX_TILE_UPDATES);
  tile_updates[1] = new ArrayDeque(MAX_TILE_UPDATES);
  
  // perform initial full scale update
  // puts flip-flops into flickering state
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      if (get_tile(x, y) == T_GATE) {
        queue_tile_update(x, y);
      }
    }
  }
}

byte lookup_tile(color c) {
  // optimize: hash map
  for (byte i = 0; i < tiles.length; i++) {
    if (tiles[i] == c)
      return i;
  }
  return -1;
}

boolean outside_bounds(int x, int y) {
  if (x < 0) return true;
  if (y < 0) return true;
  if (x >= w) return true;
  if (y >= h) return true;
  return false;
}

boolean is_active(int x, int y) {
  if (outside_bounds(x, y)) return false;
  return (grid[x + y * w] & 0x80) != 0;
}

void set_active(int x, int y, boolean a) {
  if (outside_bounds(x, y)) return;
  grid[x + y * w] &= ~0x80;
  if (a) grid[x + y * w] |= 0x80;
}

byte get_tile(int x, int y) {
  if (outside_bounds(x, y)) return T_NOTHING;
  return (byte) (grid[x + y * w] & ~0x80);
}

void queue_tile_update(int x, int y) {
  if (outside_bounds(x, y)) return;
  if (get_tile(x, y) == 0)
    return;
  tile_updates[flip ^ 1].add(new Point(x, y));
}

int num_active_adj_of_type(int x, int y, byte t) {
  int i = 0;
  if (get_tile(x + 1, y) == t) if (is_active(x + 1, y)) i++;
  if (get_tile(x - 1, y) == t) if (is_active(x - 1, y)) i++;
  if (get_tile(x, y + 1) == t) if (is_active(x, y + 1)) i++;
  if (get_tile(x, y - 1) == t) if (is_active(x, y - 1)) i++;
  return i;
}

void update_adj_of_type(int x, int y, byte t) {
  if (get_tile(x + 1, y) == t) queue_tile_update(x + 1, y);
  if (get_tile(x - 1, y) == t) queue_tile_update(x - 1, y);
  if (get_tile(x, y + 1) == t) queue_tile_update(x, y + 1);
  if (get_tile(x, y - 1) == t) queue_tile_update(x, y - 1);
}

boolean update_wires_check(int x, int y, ArrayList<Point> queue, ArrayList<Point> update_list, Point origin) {
  if (outside_bounds(x, y))
    return false;
  if (visited[x + y * w] == 1)
    return false;
  
  byte tile = get_tile(x, y);
  
  if (tile == T_WIRE) {
    // visit adj wires
    queue.add(new Point(x, y));
    visited[x + y * w] = 1;
  } else if (tile == T_CROSS) {
    // visit wires on the other side of cross, if any
    int cx = (x << 1) - origin.x, cy = (y << 1) - origin.y;
    if (get_tile(cx, cy) == T_WIRE && visited[cx + cy * w] == 0) {
      queue.add(new Point(cx, cy));
      visited[cx + cy * w] = 1;
    }
  } else if (tile == T_GATE || tile == T_SWITCH) {
    // wires only get affected by gates and switches
    if (is_active(x, y)) return true;
  } else if (tile == T_GATE_IN) {
    // wires only update gate inputs
    update_list.add(new Point(x, y));
  }
  
  return false;
}

void update_wires(int x, int y) {
  // if wire cluster is already same state as updator, ignore
  int a = num_active_adj_of_type(x, y, T_SWITCH) + num_active_adj_of_type(x, y, T_GATE);
  if (is_active(x, y) == a > 0)
    return;
  
  //println("doing beeg update at " + x + ", " + y);
  
  // the next state for all of the visited wires
  boolean state = false;
  
  ArrayList<Point> queue = new ArrayList<Point>();
  ArrayList<Point> update_list = new ArrayList<Point>();
  
  queue.add(new Point(x, y));
  visited[x + y * w] = 1;
  
  for (int i = 0; i < queue.size(); i++) {
    Point p = queue.get(i);
    
    if (update_wires_check(p.x + 1, p.y, queue, update_list, p)) state = true;
    if (update_wires_check(p.x - 1, p.y, queue, update_list, p)) state = true;
    if (update_wires_check(p.x, p.y + 1, queue, update_list, p)) state = true;
    if (update_wires_check(p.x, p.y - 1, queue, update_list, p)) state = true;
  }
  
  // apply the new state
  for (int i = 0; i < queue.size(); i++) {
    Point p = queue.get(i);
    set_active(p.x, p.y, state);
  }
  
  // send updates
  for (int i = 0; i < update_list.size(); i++) {
    Point p = update_list.get(i);
    queue_tile_update(p.x, p.y);
  }
}

void update_at(int x, int y) {
  //println("tile upd at " + x + ", " + y);
  byte tile = get_tile(x, y);
  boolean active = is_active(x, y);
  boolean next = active;
  
  switch (tile) {
  case T_WIRE:
    update_wires(x, y);
    return;
  case T_GATE_IN:
    int i = 0;
    i += num_active_adj_of_type(x, y, T_WIRE);
    i += num_active_adj_of_type(x, y, T_SWITCH);
    next = i > 0;
    break;
  case T_GATE:
    //next = (num_adj_active_of_type(x, y, (byte) T_GATE_IN) & 1) == 1; // xor
    next = num_active_adj_of_type(x, y, (byte) T_GATE_IN) >= 2 ? false : true; // nand, doesnt work with 3 inputs
    break;
  case T_SWITCH:
  case T_CROSS:
    break;
  default:
    println("update_at unk tile type: " + tile);
    break;
  }
  
  if (next != active) {
    set_active(x, y, next);
    
    switch (tile) {
    case T_GATE_IN:
      update_adj_of_type(x, y, T_GATE);
      break;
    case T_GATE:
      update_adj_of_type(x, y, T_WIRE);
      break;
    }
  }
}

int steps = 0;
long acc = 0;

void step() {
  long start = System.nanoTime();
  flip ^= 1;
  
  // clear visited
  for (int i = 0; i < w * h; i++)
    visited[i] = 0;
  
  Point p;
  while (!tile_updates[flip].isEmpty()) {
    p = tile_updates[flip].remove();
    update_at(p.x, p.y);
  }
  
  acc += System.nanoTime() - start;
  steps++;
  if (steps == 200) {
    double avg = (double) acc / (double) steps;
    println("avg nanos per step: " + avg);
    steps = 0;
    acc = 0;
  }
}

void setup() {
  size(800, 800);
  frameRate(60);
  textSize(18);
  
  steps_per_sec = speeds[selected_speed];
  reload_image();
}

double time_acc = 0;

void draw() {
  if (dragging) {
    cam_x = -mouseX + drag_x;
    cam_y = -mouseY + drag_y;
  }
  
  if (!paused) {
    time_acc += System.nanoTime() - last_draw_time;
    double single = 1000000000.0 / (double) steps_per_sec;
    
    while (time_acc >= single) {
      step();
      time_acc -= single;
    }
    
    last_draw_time = System.nanoTime();
  }
  
  background(0);
  noFill();
  stroke(#888888);
  rect(-cam_x, -cam_y, (w + 1) * cell_size, (h + 1) * cell_size);
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      byte t = get_tile(x, y);
      if (t == T_NOTHING)
        continue;
      
      boolean active = is_active(x, y);
      noStroke();
      fill(active ? active_tiles[t] : tiles[t]);
      rect(x * cell_size - cam_x, y * cell_size - cam_y, cell_size, cell_size);
    }
  }
  
  noStroke();
  fill(#FFFFFF);
  text("[q/w] speed: " + speeds[selected_speed] + " steps/sec", 16, 32);
  text("[space] " + (paused ? "unpause" : "pause"), 16, 54);
  text("[s] single step", 16, 76);
}

void keyPressed() {
  if (key == 'r') {
    reload_image();
  }
  if (keyCode == 32) {
    paused = !paused;
    last_draw_time = System.nanoTime();
  }
  if (key == 's') {
    if (paused)
      step();
  }
  if (key == 'q' && selected_speed > 0) {
    selected_speed--;
    steps_per_sec = speeds[selected_speed];
  }
  if (key == 'w' && selected_speed < speeds.length - 1) {
    selected_speed++;
    steps_per_sec = speeds[selected_speed];
  }
}

Point find_switch(int x, int y) {
  if (get_tile(x, y) == T_SWITCH) {
    return new Point(x, y);
  }
  for (int xo = -1; xo <= 1; xo++) {
    for (int yo = -1; yo <= 1; yo++) {
      if ((xo | yo) == 0)
        continue;
      if (get_tile(x + xo, y + yo) == T_SWITCH) {
        return new Point(x + xo, y + yo);
      }
    }
  }
  return null;
}

void mousePressed() {
  if (mouseButton == LEFT) {
    int x = (mouseX + cam_x) / cell_size;
    int y = (mouseY + cam_y) / cell_size;
    
    Point p = find_switch(x, y);
    if (p == null)
      return;
    x = p.x; y = p.y;
    
    set_active(x, y, !is_active(x, y));
    update_adj_of_type(x, y, T_WIRE);
    update_adj_of_type(x, y, T_GATE_IN);
  } else {
    drag_x = mouseX + cam_x;
    drag_y = mouseY + cam_y;
    dragging = true;
  }
}

void mouseReleased() {
  if (mouseButton != LEFT)
    dragging = false;
}

void mouseWheel(MouseEvent event) {
  cell_size -= event.getCount();
  if (cell_size <= 0)
    cell_size = 1;
  if (cell_size > 30)
    cell_size = 30;
}
