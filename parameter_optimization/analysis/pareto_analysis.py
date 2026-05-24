from pathlib import Path

def identify_pareto(data_x, data_y, minimize_x=True, maximize_y=True):
    # A simple pareto frontier calculator
    points = list(zip(data_x, data_y))
    pareto_front = []
    
    for i, (x1, y1) in enumerate(points):
        dominated = False
        for j, (x2, y2) in enumerate(points):
            if i == j:
                continue
            
            # check if 2 dominates 1
            better_or_equal_x = (x2 <= x1) if minimize_x else (x2 >= x1)
            better_or_equal_y = (y2 >= y1) if maximize_y else (y2 <= y1)
            
            strictly_better_x = (x2 < x1) if minimize_x else (x2 > x1)
            strictly_better_y = (y2 > y1) if maximize_y else (y2 < y1)
            
            if better_or_equal_x and better_or_equal_y and (strictly_better_x or strictly_better_y):
                dominated = True
                break
                
        if not dominated:
            pareto_front.append((x1, y1))
            
    # sort for plotting
    pareto_front.sort(key=lambda p: p[0])
    return pareto_front

def is_dominated(x1, y1, points, minimize_x, maximize_y):
    for x2, y2 in points:
        better_or_equal_x = (x2 <= x1) if minimize_x else (x2 >= x1)
        better_or_equal_y = (y2 >= y1) if maximize_y else (y2 <= y1)
        strictly_better_x = (x2 < x1) if minimize_x else (x2 > x1)
        strictly_better_y = (y2 > y1) if maximize_y else (y2 < y1)
        
        if better_or_equal_x and better_or_equal_y and (strictly_better_x or strictly_better_y):
            return True
    return False
