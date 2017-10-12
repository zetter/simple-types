require 'term'
require 'type'

def join(a, b)
  if subtype_of?(b, a)
    a
  elsif subtype_of?(a, b)
    b
  elsif a.is_a?(Type::Record) && b.is_a?(Type::Record)
    join_keys = a.members.keys & b.members.keys
    members = join_keys.map do |key|
      [key, join(a.members[key], b.members[key])]
    end.to_h
    Type::Record.new(members)
  elsif a.is_a?(Type::Function) && b.is_a?(Type::Function)
    begin
      argument_meet = meet(a.from, b.from)
    rescue TypeError
      return Type::Top
    end
    Type::Function.new(argument_meet, join(a.to, b.to))
  else
    Type::Top
  end
end

def meet(a, b)
  if subtype_of?(a, b)
    a
  elsif subtype_of?(b, a)
    b
  elsif a.is_a?(Type::Record) && b.is_a?(Type::Record)
    meet_members = a.members.merge(b.members) do |_, value_a, value_b|
      meet(value_a, value_b)
    end
    Type::Record.new(meet_members)
  elsif a.is_a?(Type::Function) && b.is_a?(Type::Function)
    Type::Function.new(join(a.from, b.from), meet(a.to, b.to))
  else
    raise TypeError, "No meet of #{a.inspect} and #{b.inspect}"
  end
end

def subtype_of?(subtype, supertype)
  if supertype == Type::Top # SA-TOP
    true
  elsif subtype == supertype # S-REFL
    true
  elsif subtype.is_a?(Type::Record) && supertype.is_a?(Type::Record)
    supertype.members.all? do |field, type|
      subtype.members.key?(field) && subtype_of?(subtype.members[field], type)
    end
  elsif subtype.is_a?(Type::Function) && supertype.is_a?(Type::Function)
    subtype_of?(supertype.from, subtype.from) &&
      subtype_of?(subtype.to, supertype.to)
  else
    false
  end
end

def type_of(term, context = {})
  case term
  when Term::True, Term::False
    Type::Boolean
  when Term::Var
    raise TypeError, "unknown variable #{term.name}" unless context.key?(term.name)

    context.fetch(term.name)
  when Term::Abs
    context_prime = context.merge(term.param => term.type)

    Type::Function.new(term.type, type_of(term.body, context_prime))
  when Term::If
    condition_type = type_of(term.condition, context)
    raise TypeError, 'non-boolean condition' unless condition_type == Type::Boolean

    consequent_type = type_of(term.consequent, context)
    alternate_type = type_of(term.alternate, context)

    join(consequent_type, alternate_type)
  when Term::Application
    left_type = type_of(term.left, context)
    raise TypeError, 'non-abstraction' unless left_type.is_a?(Type::Function)
    raise TypeError, '💩 argument' unless subtype_of?(type_of(term.right, context), left_type.from)

    left_type.to
  when Term::Record
    Type::Record.new(term.members.map { |label, member| [label, type_of(member, context)] }.to_h)
  when Term::Project
    object_type = type_of(term.object, context)
    raise TypeError, 'not a record' unless object_type.is_a?(Type::Record)
    raise TypeError, "unknown field #{term.field}" unless object_type.members.key?(term.field)

    object_type.members.fetch(term.field)
  end
end
