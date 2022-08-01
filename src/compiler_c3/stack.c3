module stack <Type>;
// Above: the parameterized type is applied to the entire module.

struct Stack
{
    usize capacity;
    usize size;
    Type* elems;
}

// The type methods offers dot syntax calls,
// so this function can either be called 
// Stack.push(&my_stack, ...) or
// my_stack.push(...)
fn void Stack.push(Stack* this, Type element)
{
    if (this.capacity == this.size)
    {
        this.capacity *= 2;
        this.elems = mem::realloc(this.elems, Type.sizeof * this.capacity);
    }
    this.elems[this.size++] = element;
}

fn Type Stack.pop(Stack* this)
{
    assert(this.size > 0);
    return this.elems[--this.size];
}

fn bool Stack.empty(Stack* this)
{
    return !this.size;
}

fn bool Stack.full(Stack* this)
{
    return this.capacity == this.size;
}

fn usize Stack.clear(Stack* this) {
    usize prev_size = this.size;
    this.size = 0;
    return prev_size;
}

// unchecked resize
fn void Stack.resize(Stack* this, usize new_capacity) {
    this.capacity = new_capacity;
    this.elems = mem::realloc(this.elems, Type.sizeof * new_capacity);
}

fn void Stack.free(Stack* this) {
    if (this.elems) {
        mem::free(this.elems);
        this.capacity = 0;
        this.size = 0;
        this.elems = (Type*)0;
    }
}