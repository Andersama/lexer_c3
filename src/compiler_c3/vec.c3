module vec <Type>;
// Above: the parameterized type is applied to the entire module.

struct Vec
{
    usize capacity;
    usize size;
    Type* elems;
}

// The type methods offers dot syntax calls,
// so this function can either be called 
// Vec.push(&my_Vec, ...) or
// my_Vec.push(...)
fn void Vec.push(Vec* this, Type element)
{
    if (this.capacity == this.size)
    {
        this.capacity *= 2;
        this.elems = mem::realloc(this.elems, Type.sizeof * this.capacity);
    }
    this.elems[this.size++] = element;
}

fn Type Vec.pop(Vec* this)
{
    assert(this.size > 0);
    return this.elems[--this.size];
}

fn bool Vec.empty(Vec* this)
{
    return !this.size;
}

fn bool Vec.full(Vec* this)
{
    return this.capacity == this.size;
}

fn usize Vec.clear(Vec* this) {
    usize prev_size = this.size;
    this.size = 0;
    return prev_size;
}
// does nothing if out of range
fn void Vec.erase(Vec* this, usize idx) {
    for (usize i = idx; (i+1) < this.size; i++) {
        this.elems[i] = this.elems[i+1];
    }
    this.size -= (idx < this.size);
}
// [first, last)
fn void Vec.erase(Vec* this, usize first, usize last) {
    usize l = last;
    usize d = 0;
    for (usize i = first; (i+1) < this.size && (l+1) < this.size; i++) {
        this.elems[i] = this.elems[l];
        d++;
    }
    this.size -= d;
}
// assigns back element to idx, erases idx
fn void Vec.quick_erase(Vec* this, usize idx) {
    assert(idx < this.size);
    this.elems[idx] = this.elems[this.size-1];
    this.size -= (idx < this.size);
}

// unchecked resize
fn void Vec.resize(Vec* this, usize new_capacity) {
    this.capacity = new_capacity;
    this.elems = mem::realloc(this.elems, Type.sizeof * new_capacity);
}

fn void Vec.free(Vec* this) {
    if (this.elems) {
        mem::free(this.elems);
        this.capacity = 0;
        this.size = 0;
        this.elems = (Type*)0;
    }
}